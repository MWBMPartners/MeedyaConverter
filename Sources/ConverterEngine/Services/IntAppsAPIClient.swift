// ============================================================================
// MeedyaConverter — IntAppsAPIClient
// (C) 2026–present MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// A thin, honest client for the MWBM `intAppsAPI` service
// (https://api.mwbmpartners.ltd) — the internal gateway that provides
// remote feature flags and update-channel metadata for MWBM Partners
// applications. This file wires up two roadmap items:
//
//   * #5 — remote feature flags (`RemoteFeatureGateProvider`, in
//     `Sources/ConverterEngine/Licensing/RemoteFeatureGateProvider.swift`,
//     is built on `fetchFeatureFlags`/`fetchFeatureFlag`).
//   * #4 — the alpha/beta update channel (`AppUpdateChecker` in the GUI
//     target calls `checkForUpdate` when the user has opted into a
//     pre-release channel).
//
// ### Contract (client-relevant subset — full OpenAPI spec lives in the
// intAppsAPI repository, not this one):
//
//   GET /v1/features/{app_slug}
//     -> { success, data: { app_slug, features: [FeatureFlag], count } }
//   GET /v1/features/{app_slug}/{feature_key}
//     -> { success, data: FeatureFlag }
//   GET /v1/updates/{app_slug}/{channel}?version=<semver>
//     -> { success, data: UpdateChannel & { update_available, client_version } }
//
// Every endpoint used here is a GET, which intAppsAPI's three-factor app
// auth (`X-App-ID` + `User-Agent` prefix + `X-API-Key`) accepts without an
// HMAC signature — HMAC (`X-Signature`/`X-Timestamp`) is only required for
// mutating POST/PATCH/DELETE requests, none of which this client makes.
//
// ### Honesty contract
// Every method either returns data the server actually sent, or throws
// `IntAppsAPIError` describing the real failure (HTTP status, decoded
// `error.message`, transport error, or decode failure). Nothing is ever
// fabricated — a dead or misconfigured API surfaces as a thrown error,
// never as a silently-substituted default. (Callers that want a
// fail-safe default — e.g. `RemoteFeatureGateProvider` — apply that
// policy themselves, on top of this client's honest results.)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - JSONValue
// ---------------------------------------------------------------------------
/// A minimal type-erased JSON value, used only for `FeatureFlag.metadata`
/// (an arbitrary, admin-authored JSON object per the OpenAPI schema —
/// `"metadata": { "type": "object", "nullable": true }`, no fixed shape).
///
/// `Codable`'s `Any` can't be synthesised, and this codebase has no JSON
/// library dependency to reach for (see the commented-out `Yams`/
/// `ZIPFoundation` entries in `Package.swift` — third-party dependencies
/// are added deliberately, not by default), so this is a small, local,
/// fully `Sendable` stand-in sufficient for round-tripping whatever the
/// admin dashboard puts in a flag's metadata.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // Order matters: `Bool` must be tried before `Double`/`Int`-ish
        // decoding, since JSONDecoder will NOT coerce "true"/"false" into
        // a Double, so there's no ambiguity risk trying Bool first.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value in FeatureFlag.metadata"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):  try container.encode(value)
        case .number(let value):  try container.encode(value)
        case .bool(let value):    try container.encode(value)
        case .object(let value):  try container.encode(value)
        case .array(let value):   try container.encode(value)
        case .null:                try container.encodeNil()
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - FeatureFlag
// ---------------------------------------------------------------------------
/// A single remote feature flag, as returned by `GET /v1/features/{app_slug}`
/// and `GET /v1/features/{app_slug}/{feature_key}`.
///
/// `enabled` is the server's already-computed *effective* state — it has
/// already folded in any `enabled_at`/`disabled_at` scheduling, so callers
/// never need to re-derive availability from the timestamps themselves.
public struct FeatureFlag: Codable, Sendable, Equatable {

    /// The flag's stable identifier (e.g. `"video-upload"`).
    public let featureKey: String

    /// Optional admin-facing display label. Not localised; not intended
    /// for direct end-user display.
    public let label: String?

    /// The effective enabled state, already accounting for scheduling.
    public let enabled: Bool

    /// Scheduled enable time, if the flag has one configured.
    public let enabledAt: Date?

    /// Scheduled disable time, if the flag has one configured.
    public let disabledAt: Date?

    /// Free-form admin-authored metadata, if any.
    public let metadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case featureKey = "feature_key"
        case label
        case enabled
        case enabledAt = "enabled_at"
        case disabledAt = "disabled_at"
        case metadata
    }

    public init(
        featureKey: String,
        label: String? = nil,
        enabled: Bool,
        enabledAt: Date? = nil,
        disabledAt: Date? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.featureKey = featureKey
        self.label = label
        self.enabled = enabled
        self.enabledAt = enabledAt
        self.disabledAt = disabledAt
        self.metadata = metadata
    }
}

// ---------------------------------------------------------------------------
// MARK: - UpdateCheckResult
// ---------------------------------------------------------------------------
/// The result of `GET /v1/updates/{app_slug}/{channel}?version=<semver>` —
/// the `UpdateChannel` schema flattened together with the two fields the
/// server adds when a `version` query parameter is supplied (which this
/// client always supplies, so both are always populated in practice).
public struct UpdateCheckResult: Codable, Sendable, Equatable {

    /// The channel name slug this result is for (e.g. `"alpha"`).
    public let channel: String

    /// The current published version on this channel, if the maintainer
    /// has configured one yet.
    public let currentVersion: String?

    /// Where to send the user to obtain the update.
    public let updateURL: URL

    /// When the channel's published version last changed.
    public let updatedAt: Date?

    /// Whether `currentVersion` is newer than the `client_version` the
    /// caller supplied.
    public let updateAvailable: Bool

    /// Echo of the client version the caller sent in the `version` query
    /// parameter — useful for confirming the server parsed the intended
    /// version rather than defaulting silently.
    public let clientVersion: String?

    enum CodingKeys: String, CodingKey {
        case channel
        case currentVersion = "current_version"
        case updateURL = "update_url"
        case updatedAt = "updated_at"
        case updateAvailable = "update_available"
        case clientVersion = "client_version"
    }

    public init(
        channel: String,
        currentVersion: String?,
        updateURL: URL,
        updatedAt: Date?,
        updateAvailable: Bool,
        clientVersion: String?
    ) {
        self.channel = channel
        self.currentVersion = currentVersion
        self.updateURL = updateURL
        self.updatedAt = updatedAt
        self.updateAvailable = updateAvailable
        self.clientVersion = clientVersion
    }
}

// ---------------------------------------------------------------------------
// MARK: - IntAppsAPIError
// ---------------------------------------------------------------------------
/// A real failure talking to intAppsAPI. Every case carries information
/// the server or `URLSession` actually reported — mirrors the "never
/// fabricate" contract `CloudUploadExecutor.UploadError` and
/// `WebhookSender.WebhookError` already establish elsewhere in this
/// module.
public enum IntAppsAPIError: LocalizedError, Sendable, Equatable {

    /// The response was not an `HTTPURLResponse` at all (should not
    /// happen for `https://` requests, but `URLSession` does not
    /// statically guarantee it).
    case invalidResponse

    /// The server responded with a non-2xx HTTP status. `message` is the
    /// real decoded `error.message` from the response body when present,
    /// else a truncated raw-body snippet, else `nil`.
    case httpError(statusCode: Int, message: String?)

    /// The server responded 2xx but the envelope's `success` field was
    /// `false`. `message` is the real decoded `error.message`, if any.
    case apiFailure(message: String?)

    /// A 2xx, `success: true` response whose `data` payload could not be
    /// decoded into the expected shape.
    case decodingFailed(String)

    /// A transport-level failure with no HTTP response at all — DNS,
    /// TLS, timeout, or connection reset.
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "intAppsAPI returned a response that was not a valid HTTP response."
        case .httpError(let statusCode, let message):
            return "intAppsAPI request failed with HTTP \(statusCode)\(message.map { ": \($0)" } ?? "")"
        case .apiFailure(let message):
            return "intAppsAPI reported failure\(message.map { ": \($0)" } ?? ".")"
        case .decodingFailed(let message):
            return "Failed to decode intAppsAPI response: \(message)"
        case .transport(let message):
            return "intAppsAPI request failed: \(message)"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - IntAppsAPICredentials
// ---------------------------------------------------------------------------
/// The three-factor app identity intAppsAPI requires on every request,
/// plus the `app_slug` used to build request paths.
///
/// None of these are baked into source — see `IntAppsAPICredentialLoader`
/// for where they actually come from (Keychain, then environment
/// variables for local development). This struct is deliberately just a
/// plain data holder so tests can construct one directly without going
/// through the Keychain at all.
public struct IntAppsAPICredentials: Sendable, Equatable {

    /// The app's slug, used in request paths (e.g. `"meedyaconverter"`).
    public let appSlug: String

    /// The app's registered UUID, sent as `X-App-ID`.
    public let appID: String

    /// The app's API key, sent as `X-API-Key`.
    public let apiKey: String

    /// The registered `User-Agent` prefix. intAppsAPI checks
    /// `str_starts_with($userAgent, $expectedPrefix)`, so this only needs
    /// to be a prefix of whatever `User-Agent` the client actually sends
    /// — see `IntAppsAPIClient.userAgentHeaderValue`.
    public let userAgentPrefix: String

    public init(appSlug: String, appID: String, apiKey: String, userAgentPrefix: String) {
        self.appSlug = appSlug
        self.appID = appID
        self.apiKey = apiKey
        self.userAgentPrefix = userAgentPrefix
    }
}

// ---------------------------------------------------------------------------
// MARK: - IntAppsAPICredentialLoader
// ---------------------------------------------------------------------------
/// Resolves `IntAppsAPICredentials` from the app's established secret
/// storage, following the same layering `APIKeyManager` already uses for
/// every other provider:
///
///   1. **Keychain**, via `APIKeyManager`'s `.intAppsAPI` provider case —
///      the production path. A maintainer provisions this the same way
///      any other cloud/metadata provider key is added (see
///      `CloudStorageView`'s "add key" flow for the established UI
///      pattern; intAppsAPI does not yet have an equivalent settings
///      screen, so provisioning today is via `APIKeyManager.storeKey(_:)`
///      directly — see the field-mapping note on the `.intAppsAPI` case
///      in `APIKeyManager.swift`).
///   2. **Environment variables**, for local development — mirrors the
///      general env-var fallback pattern already used for platform paths
///      in `PlatformSupport.swift`.
///
/// Returning `nil` from `load(...)` means "not configured" — every
/// consumer (`IntAppsAPIClient.configured(...)`, and transitively
/// `RemoteFeatureGateProvider` / `AppUpdateChecker`) MUST treat `nil` as
/// "stay completely dormant: no network calls, no errors surfaced" per
/// the roadmap #4/#5 requirement that an unprovisioned intAppsAPI never
/// changes the app's behaviour.
public enum IntAppsAPICredentialLoader {

    /// Environment variable names for the local-development fallback.
    /// Namespaced under `MEEDYACONVERTER_` to avoid collisions with any
    /// other tool's environment on a developer's machine.
    private static let envAppSlug = "MEEDYACONVERTER_INTAPPSAPI_APP_SLUG"
    private static let envAppID = "MEEDYACONVERTER_INTAPPSAPI_APP_ID"
    private static let envAPIKey = "MEEDYACONVERTER_INTAPPSAPI_API_KEY"
    private static let envUserAgentPrefix = "MEEDYACONVERTER_INTAPPSAPI_USER_AGENT_PREFIX"

    /// Fallback `User-Agent` prefix used when a credential source
    /// supplies the other three factors but not an explicit prefix.
    /// Whatever the maintainer actually registers server-side for this
    /// app's `user_agent_prefix` MUST start with (or equal) this value,
    /// or every request will fail the three-factor auth check with a
    /// generic 403 — see `AuthMiddleware`'s Factor 2 check in the
    /// intAppsAPI service.
    public static let defaultUserAgentPrefix = "MeedyaConverter"

    /// Resolve credentials, preferring the Keychain over environment
    /// variables. Returns `nil` if neither source has a complete set.
    ///
    /// - Parameters:
    ///   - apiKeyManager: The manager to read the `.intAppsAPI` Keychain
    ///     entry from. Defaults to a fresh `APIKeyManager()` against the
    ///     standard on-disk location + Keychain service; tests inject an
    ///     isolated instance.
    ///   - environment: The environment variables to check as a
    ///     fallback. Defaults to the real process environment; tests
    ///     inject a fixed dictionary so they never depend on (or
    ///     pollute) the host machine's actual environment.
    public static func load(
        apiKeyManager: APIKeyManager = APIKeyManager(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> IntAppsAPICredentials? {
        if let fromKeychain = loadFromKeychain(apiKeyManager: apiKeyManager) {
            return fromKeychain
        }
        return loadFromEnvironment(environment)
    }

    /// Reads the `.intAppsAPI` entry `APIKeyManager` may have stored.
    /// Field mapping (documented in full on the `APIKeyProvider.intAppsAPI`
    /// case, since `StoredAPIKey`'s shape is shared across every
    /// provider and was not changed for this integration):
    ///   `apiKey` → `X-API-Key`, `secretKey` → `X-App-ID`,
    ///   `label` → `app_slug`, `refreshToken` → `User-Agent` prefix
    ///   (falls back to `defaultUserAgentPrefix` when absent/empty).
    private static func loadFromKeychain(apiKeyManager: APIKeyManager) -> IntAppsAPICredentials? {
        guard let stored = apiKeyManager.key(for: .intAppsAPI), stored.isValid else {
            return nil
        }
        guard let appSlug = stored.label, !appSlug.isEmpty else { return nil }
        guard let appID = stored.secretKey, !appID.isEmpty else { return nil }
        guard !stored.apiKey.isEmpty else { return nil }

        let userAgentPrefix = (stored.refreshToken?.isEmpty == false)
            ? stored.refreshToken!
            : defaultUserAgentPrefix

        return IntAppsAPICredentials(
            appSlug: appSlug,
            appID: appID,
            apiKey: stored.apiKey,
            userAgentPrefix: userAgentPrefix
        )
    }

    /// Reads the `MEEDYACONVERTER_INTAPPSAPI_*` environment variables.
    /// All three of app slug / app ID / API key must be present and
    /// non-empty; the User-Agent prefix is optional and falls back to
    /// `defaultUserAgentPrefix`.
    private static func loadFromEnvironment(_ environment: [String: String]) -> IntAppsAPICredentials? {
        guard let appSlug = environment[envAppSlug], !appSlug.isEmpty,
              let appID = environment[envAppID], !appID.isEmpty,
              let apiKey = environment[envAPIKey], !apiKey.isEmpty
        else {
            return nil
        }

        let userAgentPrefix = environment[envUserAgentPrefix].flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultUserAgentPrefix

        return IntAppsAPICredentials(
            appSlug: appSlug,
            appID: appID,
            apiKey: apiKey,
            userAgentPrefix: userAgentPrefix
        )
    }
}

// ---------------------------------------------------------------------------
// MARK: - IntAppsAPIClient
// ---------------------------------------------------------------------------
/// A small `URLSession`-backed client for the three intAppsAPI endpoints
/// MeedyaConverter needs. All three are GETs, so no HMAC signing is
/// required (see the file overview above).
///
/// A plain struct rather than an actor or class: every stored property is
/// an immutable `let` set once at `init`, matching the reasoning already
/// documented on `CloudUploadExecutor` and `WebhookSender` elsewhere in
/// this module — there is no mutable state to protect, so the type is
/// trivially safe to share across concurrency domains. `@unchecked
/// Sendable` for the same reason those two types use it: `URLSession` is
/// documented thread-safe, but this file does not depend on the SDK
/// having that formally annotated for the compiler.
public struct IntAppsAPIClient: @unchecked Sendable {

    /// Production base URL, per the OpenAPI `servers` entry.
    public static let productionBaseURL = URL(string: "https://api.mwbmpartners.ltd")!

    /// The credentials used to authenticate every request. Exposed so
    /// callers (e.g. `RemoteFeatureGateProvider`, `AppUpdateChecker`) can
    /// read `credentials.appSlug` without threading it through
    /// separately.
    public let credentials: IntAppsAPICredentials

    private let session: URLSession
    private let baseURL: URL
    private let timeoutInterval: TimeInterval

    /// - Parameters:
    ///   - credentials: The three-factor app identity + app slug. Never
    ///     loaded implicitly here — see `configured(...)` for the
    ///     dormancy-aware factory that resolves credentials from the
    ///     Keychain/environment and returns `nil` when unconfigured.
    ///   - session: The `URLSession` to execute requests on. Defaults to
    ///     `.shared`; tests inject a session configured with a
    ///     `URLProtocol` mock (see `IntAppsAPIClientTests`) so no real
    ///     network I/O ever occurs.
    ///   - baseURL: The API's base URL. Defaults to
    ///     `productionBaseURL`; tests override it (harmlessly, since the
    ///     mock intercepts every request regardless of host).
    ///   - timeoutInterval: Per-request timeout in seconds. Defaults to
    ///     10 — long enough for a slow-but-alive API, short enough that a
    ///     dead API can never hang the UI (the Settings → Updates check
    ///     and the startup feature-flag refresh both run off the main
    ///     thread via `async`, but an unbounded hang would still starve
    ///     whichever `Task` is awaiting the result).
    public init(
        credentials: IntAppsAPICredentials,
        session: URLSession = .shared,
        baseURL: URL = IntAppsAPIClient.productionBaseURL,
        timeoutInterval: TimeInterval = 10
    ) {
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
    }

    // -----------------------------------------------------------------
    // MARK: - Dormancy-aware factory
    // -----------------------------------------------------------------

    /// Attempts to build a client from the Keychain / environment via
    /// `IntAppsAPICredentialLoader`. Returns `nil` when intAppsAPI is not
    /// configured for this app yet — the single chokepoint every caller
    /// in this codebase uses to decide "dormant vs active", so the
    /// dormancy rule only has to be implemented once.
    ///
    /// - Parameters:
    ///   - apiKeyManager: Forwarded to `IntAppsAPICredentialLoader.load`.
    ///   - environment: Forwarded to `IntAppsAPICredentialLoader.load`.
    ///   - session: Forwarded to `init`.
    ///   - baseURL: Forwarded to `init`.
    ///   - timeoutInterval: Forwarded to `init`.
    /// - Returns: A configured client, or `nil` if credentials are absent.
    public static func configured(
        apiKeyManager: APIKeyManager = APIKeyManager(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared,
        baseURL: URL = IntAppsAPIClient.productionBaseURL,
        timeoutInterval: TimeInterval = 10
    ) -> IntAppsAPIClient? {
        guard let credentials = IntAppsAPICredentialLoader.load(
            apiKeyManager: apiKeyManager,
            environment: environment
        ) else {
            return nil
        }
        return IntAppsAPIClient(
            credentials: credentials,
            session: session,
            baseURL: baseURL,
            timeoutInterval: timeoutInterval
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Public API
    // -----------------------------------------------------------------

    /// `GET /v1/features/{app_slug}` — every feature flag for the app.
    ///
    /// - Parameter appSlug: The app slug to query. Callers normally pass
    ///   `credentials.appSlug` (the loader already validated it's
    ///   non-empty), but this stays a parameter — matching the task
    ///   contract — so a single client instance could, in principle,
    ///   query on behalf of a different slug than its own credentials'
    ///   home app, if intAppsAPI ever supports that.
    /// - Returns: All feature flags currently configured for the app.
    /// - Throws: `IntAppsAPIError` on any non-success outcome. Never
    ///   returns a fabricated or partial flag list.
    public func fetchFeatureFlags(appSlug: String) async throws -> [FeatureFlag] {
        let url = try makeURL(path: "v1/features/\(pathEscape(appSlug))")
        let envelope: FeatureListEnvelope = try await performGET(url)
        guard envelope.success, let data = envelope.data else {
            throw IntAppsAPIError.apiFailure(message: envelope.error?.message)
        }
        return data.features
    }

    /// `GET /v1/features/{app_slug}/{feature_key}` — a single flag.
    ///
    /// - Parameters:
    ///   - appSlug: The app slug to query.
    ///   - key: The feature flag's key (e.g. `"video-upload"`).
    /// - Returns: The flag's current effective state.
    /// - Throws: `IntAppsAPIError` on any non-success outcome (including
    ///   a 404 for an unknown key). Never returns a fabricated flag.
    public func fetchFeatureFlag(appSlug: String, key: String) async throws -> FeatureFlag {
        let url = try makeURL(path: "v1/features/\(pathEscape(appSlug))/\(pathEscape(key))")
        let envelope: FeatureEnvelope = try await performGET(url)
        guard envelope.success, let flag = envelope.data else {
            throw IntAppsAPIError.apiFailure(message: envelope.error?.message)
        }
        return flag
    }

    /// `GET /v1/updates/{app_slug}/{channel}?version=<semver>` — checks
    /// whether a newer build is published on `channel`.
    ///
    /// - Parameters:
    ///   - appSlug: The app slug to query.
    ///   - channel: The channel name slug (e.g. `"alpha"`, `"beta"`,
    ///     `"stable"`). Must match `^[a-z0-9-]+$` per the server's
    ///     validation — callers pass the raw channel identifier, not a
    ///     display name.
    ///   - currentVersion: The running app's SemVer version. Always sent
    ///     as the `version` query parameter, so `update_available` and
    ///     `client_version` are always populated in the response.
    /// - Returns: The channel's current state plus the update-available
    ///   verdict.
    /// - Throws: `IntAppsAPIError` on any non-success outcome. Never
    ///   fabricates an "update available" or "up to date" verdict.
    public func checkForUpdate(
        appSlug: String,
        channel: String,
        currentVersion: String
    ) async throws -> UpdateCheckResult {
        var url = try makeURL(path: "v1/updates/\(pathEscape(appSlug))/\(pathEscape(channel))")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw IntAppsAPIError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "version", value: currentVersion)]
        guard let resolvedURL = components.url else {
            throw IntAppsAPIError.invalidResponse
        }
        url = resolvedURL

        let envelope: UpdateCheckEnvelope = try await performGET(url)
        guard envelope.success, let result = envelope.data else {
            throw IntAppsAPIError.apiFailure(message: envelope.error?.message)
        }
        return result
    }

    // -----------------------------------------------------------------
    // MARK: - Private — request plumbing
    // -----------------------------------------------------------------

    /// Builds a full request URL from a path relative to `baseURL`.
    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw IntAppsAPIError.invalidResponse
        }
        return url
    }

    /// Percent-escapes a path segment, additionally excluding `/` from
    /// the allowed set (unlike `.urlPathAllowed`, which permits `/`
    /// unescaped) — `appSlug`/`channel`/`key` are single path segments,
    /// and this stops any of them from smuggling in extra path
    /// components even though every current caller already only ever
    /// passes simple slugs.
    private func pathEscape(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// The `User-Agent` header value sent on every request: the
    /// registered prefix, plus a version suffix for observability on the
    /// server side. intAppsAPI only checks that the header *starts with*
    /// `credentials.userAgentPrefix`, so appending anything after it is
    /// always safe.
    private var userAgentHeaderValue: String {
        "\(credentials.userAgentPrefix)/\(ConverterEngine.version)"
    }

    /// Performs a single authenticated GET request and decodes the
    /// response as `T`. Shared by every public method above.
    ///
    /// - Parameter url: The full request URL.
    /// - Returns: The decoded envelope. Callers still need to check
    ///   `envelope.success` themselves — this method only handles
    ///   transport and HTTP-status-level failures, since the envelope
    ///   shape (and therefore what "success" means) differs per caller.
    /// - Throws: `IntAppsAPIError`.
    private func performGET<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.setValue(credentials.appID, forHTTPHeaderField: "X-App-ID")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(userAgentHeaderValue, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw IntAppsAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw IntAppsAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard (200...299).contains(http.statusCode) else {
            // Try to surface the server's real error message; fall back
            // to a raw body snippet, then to no message at all — never a
            // fabricated one.
            if let errorEnvelope = try? decoder.decode(GenericErrorEnvelope.self, from: data),
               let message = errorEnvelope.error?.message {
                throw IntAppsAPIError.httpError(statusCode: http.statusCode, message: message)
            }
            let bodySnippet = String(data: data.prefix(500), encoding: .utf8)
            throw IntAppsAPIError.httpError(statusCode: http.statusCode, message: bodySnippet)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw IntAppsAPIError.decodingFailed(String(describing: error))
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Response envelopes (private decoding shapes)
// ---------------------------------------------------------------------------
// These mirror the `{ success, data, error }` envelope every intAppsAPI
// response uses, specialised per endpoint's `data` shape. Kept private —
// callers only ever see the unwrapped `FeatureFlag`/`[FeatureFlag]`/
// `UpdateCheckResult` values `IntAppsAPIClient`'s public methods return.
// ---------------------------------------------------------------------------

/// `{ code, message }` — the `error` object on a failure envelope.
private struct APIErrorPayload: Decodable {
    let code: String?
    let message: String?
}

/// The minimal envelope shape used to extract an error message from a
/// non-2xx response, regardless of which endpoint produced it.
private struct GenericErrorEnvelope: Decodable {
    let success: Bool?
    let error: APIErrorPayload?
}

/// Envelope for `GET /v1/features/{app_slug}`.
private struct FeatureListEnvelope: Decodable {
    let success: Bool
    let data: FeatureListData?
    let error: APIErrorPayload?
}

private struct FeatureListData: Decodable {
    let appSlug: String
    let features: [FeatureFlag]
    let count: Int

    enum CodingKeys: String, CodingKey {
        case appSlug = "app_slug"
        case features
        case count
    }
}

/// Envelope for `GET /v1/features/{app_slug}/{feature_key}`.
private struct FeatureEnvelope: Decodable {
    let success: Bool
    let data: FeatureFlag?
    let error: APIErrorPayload?
}

/// Envelope for `GET /v1/updates/{app_slug}/{channel}`.
private struct UpdateCheckEnvelope: Decodable {
    let success: Bool
    let data: UpdateCheckResult?
    let error: APIErrorPayload?
}
