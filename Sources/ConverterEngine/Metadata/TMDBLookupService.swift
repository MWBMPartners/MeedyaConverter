// ============================================================================
// MeedyaConverter — TMDB lookup (Issue #205)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The first of the KEYED metadata providers to actually execute. Until now
// `TMDBClient` built URLs and nothing ever sent them, so the whole video
// metadata path was unreachable — see #205.
//
// Mirrors `MusicBrainzLookupService`: requests go through the injected
// `MetadataHTTPClient` seam, statuses map to typed errors, parsing is a pure
// static function, and cancellation is rethrown untouched. Anything that can
// be tested without a network is a `static func`.
//
// ⚠️ TWO THINGS HERE ARE ABOUT THE API KEY, AND BOTH MATTER.
//
// 1. TMDB issues TWO different credentials and people paste whichever they
//    find first: a v3 API key (32 hex characters, sent as a query
//    parameter) and a v4 read access token (a JWT, sent as an
//    `Authorization: Bearer` header). Both work against these endpoints.
//    Accepting only one would reject a perfectly valid key with a confusing
//    "unauthorized", so this detects which it has been given.
//
// 2. A v3 key travels in the URL, and URLs end up in logs, proxies and crash
//    reports. So NO error thrown from this file ever carries a URL — errors
//    name the endpoint (`search/movie`) instead, and `redacting(_:)` is
//    applied to any server text before it is surfaced. When the caller has a
//    v4 token the header form is used, which keeps the secret out of the URL
//    entirely; that is why the token form is preferred when both would work.
// ============================================================================

import Foundation

// MARK: - TMDBLookupError

public enum TMDBLookupError: Error, Sendable, Equatable, LocalizedError {
    /// No key configured. Distinct from `.unauthorized`: nothing was sent.
    case missingAPIKey
    /// Nothing worth searching for.
    case emptyQuery
    /// The endpoint URL could not be formed. Carries the endpoint NAME, never
    /// the URL — the URL may contain the API key.
    case invalidEndpoint(String)
    /// HTTP 401 — TMDB rejected the key.
    case unauthorized
    /// HTTP 404 — no such title.
    case notFound
    /// HTTP 429 — asked to slow down.
    case rateLimited
    case httpStatus(statusCode: Int, bodySnippet: String)
    case transport(String)
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No TMDB API key is set. Add one in Settings before looking films up."
        case .emptyQuery:
            return "There was nothing to search for."
        case .invalidEndpoint(let endpoint):
            return "The TMDB request for \(endpoint) could not be built."
        case .unauthorized:
            return "TMDB rejected the API key. Check it in Settings."
        case .notFound:
            return "TMDB has nothing under that id."
        case .rateLimited:
            return "TMDB is asking us to slow down. Try again shortly."
        case .httpStatus(let statusCode, let bodySnippet):
            return "TMDB returned HTTP \(statusCode): \(bodySnippet)"
        case .transport(let message):
            return "Could not reach TMDB: \(message)"
        case .malformedResponse(let message):
            return "TMDB returned a response that could not be read: \(message)"
        }
    }
}

// MARK: - TMDBLookupService

/// Executes real TMDB searches and detail fetches.
public struct TMDBLookupService: Sendable {

    private let apiKey: String
    private let httpClient: any MetadataHTTPClient

    public init(
        apiKey: String,
        httpClient: any MetadataHTTPClient = URLSessionMetadataHTTPClient()
    ) {
        self.apiKey = Self.cleanedCredential(apiKey)
        self.httpClient = httpClient
    }

    /// Tidy a pasted credential into the form TMDB expects.
    ///
    /// Two paste mistakes are common enough to be worth handling rather than
    /// failing on: copying `Bearer eyJ…` verbatim out of the documentation,
    /// and copying a read access token out of a wrapped web page so it
    /// carries interior line breaks. Left alone, the first is treated as a v3
    /// key and lands in the URL (rejected), and the second puts a newline in
    /// an HTTP header.
    public static func cleanedCredential(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Bearer ", "bearer ", "BEARER "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
            break
        }
        // Remove any remaining whitespace ANYWHERE: no valid TMDB credential
        // contains any, and a stray newline in a header is a hard failure.
        return value.filter { !$0.isWhitespace }
    }

    // MARK: Credentials (pure)

    /// Whether `key` is a v4 read access token rather than a v3 API key.
    ///
    /// v4 tokens are JWTs — three dot-separated base64url segments, the first
    /// of which decodes from `{"` and so always begins `eyJ`. v3 keys are 32
    /// hex characters and contain no dots, so the two can never be confused.
    public static func usesBearerToken(_ key: String) -> Bool {
        let trimmed = cleanedCredential(key)
        return trimmed.hasPrefix("eyJ") && trimmed.split(separator: ".").count == 3
    }

    /// Replaces the API key wherever it appears in `text`.
    ///
    /// Belt and braces: no code path here is meant to put the key into a
    /// message, but server text is outside our control and this is the last
    /// place to catch it before it reaches a screen or a log.
    static func redacting(_ text: String, key: String) -> String {
        guard !key.isEmpty else { return text }
        return text.replacingOccurrences(of: key, with: "<redacted>")
    }

    /// `redacting(_:key:)` using THIS service's own key.
    ///
    /// Exists for the auto-tag runner (#508, `AutoTagRunner`), which passes
    /// every failure reason through it as a second guard before the reason
    /// can reach the Activity Log. The runner is handed a service, never the
    /// key itself — keeping the key out of `AutoTagRequest` was deliberate —
    /// so without this it would have no way to apply the redaction.
    ///
    /// Internal, not public: it does not reveal the key, but nothing outside
    /// this module has any reason to call it.
    func redactingKey(in text: String) -> String {
        Self.redacting(text, key: apiKey)
    }

    // MARK: Request building (pure)

    /// Build a request for a TMDB path plus query items.
    ///
    /// Adds the credential in whichever form suits the key: a `Bearer` header
    /// for a v4 token (which keeps it out of the URL), or an `api_key` query
    /// item for a v3 key (which is the only form v3 accepts).
    public static func buildRequest(
        path: String,
        queryItems: [URLQueryItem],
        apiKey: String
    ) -> URLRequest? {
        let trimmedKey = cleanedCredential(apiKey)
        guard var components = URLComponents(string: "\(MetadataSource.tmdb.baseURL)\(path)") else {
            return nil
        }

        var items = queryItems
        if !usesBearerToken(trimmedKey) {
            items.append(URLQueryItem(name: "api_key", value: trimmedKey))
        }
        // URLComponents percent-encodes the values for us; hand-built query
        // strings are where encoding bugs with apostrophes and ampersands in
        // film titles come from.
        components.queryItems = items

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if usesBearerToken(trimmedKey) {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: Searching

    /// Search TMDB's films.
    ///
    /// ⚠️ Search results carry NO running time — TMDB only returns that from
    /// the details endpoint. Running time is the strongest signal
    /// `DiscIdentifier.rank` has, so anything identifying a disc must call
    /// `withRuntimes(_:)` on the results before ranking them, or every
    /// candidate will score alike.
    public func searchMovies(
        title: String,
        year: Int? = nil,
        language: String = "en-US"
    ) async throws -> [MetadataResult] {
        try await search(title: title, year: year, language: language, kind: .movie)
    }

    /// Search TMDB's television series. Same running-time caveat as above.
    public func searchTVShows(
        title: String,
        year: Int? = nil,
        language: String = "en-US"
    ) async throws -> [MetadataResult] {
        try await search(title: title, year: year, language: language, kind: .tvShow)
    }

    private func search(
        title: String,
        year: Int?,
        language: String,
        kind: MediaLookupType
    ) async throws -> [MetadataResult] {
        guard !apiKey.isEmpty else { throw TMDBLookupError.missingAPIKey }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw TMDBLookupError.emptyQuery }

        let path = kind == .movie ? "/search/movie" : "/search/tv"
        var items = [
            URLQueryItem(name: "query", value: trimmedTitle),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        if let year {
            // The two endpoints spell the year filter differently.
            items.append(URLQueryItem(
                name: kind == .movie ? "year" : "first_air_date_year",
                value: String(year)
            ))
        }

        let data = try await send(path: path, queryItems: items, endpointName: path)
        return try Self.parseSearchResults(data, kind: kind)
    }

    // MARK: Details (the only source of running time)

    /// Fetch one film's details, including its running time.
    public func movieDetails(id: Int, language: String = "en-US") async throws -> MetadataResult {
        guard !apiKey.isEmpty else { throw TMDBLookupError.missingAPIKey }
        let data = try await send(
            path: "/movie/\(id)",
            queryItems: [URLQueryItem(name: "language", value: language)],
            endpointName: "movie/\(id)"
        )
        return try Self.parseMovieDetails(data)
    }

    /// Fill in running times for the first `limit` results.
    ///
    /// Costs one request per result, so it is capped. Results beyond the cap
    /// are returned unchanged rather than dropped — a candidate without a
    /// running time still ranks on its title, just less strongly.
    ///
    /// A failure on an individual detail fetch is swallowed deliberately:
    /// losing one running time should degrade the ranking, not abandon a
    /// search that already succeeded. Cancellation still propagates.
    public func withRuntimes(
        _ results: [MetadataResult],
        limit: Int = 5,
        language: String = "en-US"
    ) async throws -> [MetadataResult] {
        guard limit > 0 else { return results }

        var enriched: [MetadataResult] = []
        enriched.reserveCapacity(results.count)

        for (index, result) in results.enumerated() {
            guard index < limit,
                  result.runtimeMinutes == nil,
                  result.source == .tmdb,
                  let id = Int(result.externalId)
            else {
                enriched.append(result)
                continue
            }

            do {
                let details = try await movieDetails(id: id, language: language)
                var merged = result
                merged.runtimeMinutes = details.runtimeMinutes
                if merged.genres.isEmpty { merged.genres = details.genres }
                enriched.append(merged)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                enriched.append(result)
            }
        }

        return enriched
    }

    // MARK: Transport

    /// Send a request and map the response status onto a typed error.
    /// `endpointName` is used in errors INSTEAD of the URL, which may carry
    /// the API key.
    private func send(
        path: String,
        queryItems: [URLQueryItem],
        endpointName: String
    ) async throws -> Data {
        guard let request = Self.buildRequest(path: path, queryItems: queryItems, apiKey: apiKey) else {
            throw TMDBLookupError.invalidEndpoint(endpointName)
        }

        let result: (Data, HTTPURLResponse)
        do {
            result = try await httpClient.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TMDBLookupError.transport(
                Self.redacting(error.localizedDescription, key: apiKey)
            )
        }

        let (data, response) = result
        switch response.statusCode {
        case 200...299:
            return data
        case 401:
            throw TMDBLookupError.unauthorized
        case 404:
            throw TMDBLookupError.notFound
        case 429:
            throw TMDBLookupError.rateLimited
        default:
            throw TMDBLookupError.httpStatus(
                statusCode: response.statusCode,
                bodySnippet: Self.bodySnippet(data, redactingKey: apiKey)
            )
        }
    }

    /// A short, safe excerpt of a server error body.
    ///
    /// ⚠️ REDACTS FIRST, THEN TRUNCATES — the order is the whole point. A
    /// server that echoes the request URL (a proxy, a captive portal) sends
    /// back `api_key=<32 hex characters>` verbatim. Truncating first can cut
    /// through the middle of that key, leaving a 31-character fragment that
    /// `replacingOccurrences(of: key)` can no longer match — and 31 of 32 hex
    /// characters is, for practical purposes, the key. Redacting the whole
    /// body before it is cut means there is no fragment to survive.
    static func bodySnippet(_ data: Data, redactingKey key: String) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        return String(redacting(text, key: key).prefix(200))
    }

    // MARK: Parsing (pure)

    private struct SearchEnvelope: Decodable {
        let results: [Row]

        struct Row: Decodable {
            let id: Int
            // Films use `title`/`release_date`; series use `name`/`first_air_date`.
            let title: String?
            let name: String?
            let originalTitle: String?
            let originalName: String?
            let overview: String?
            let posterPath: String?
            let backdropPath: String?
            let releaseDate: String?
            let firstAirDate: String?
            let voteAverage: Double?

            enum CodingKeys: String, CodingKey {
                case id, title, name, overview
                case originalTitle = "original_title"
                case originalName = "original_name"
                case posterPath = "poster_path"
                case backdropPath = "backdrop_path"
                case releaseDate = "release_date"
                case firstAirDate = "first_air_date"
                case voteAverage = "vote_average"
            }
        }
    }

    private struct DetailsEnvelope: Decodable {
        let id: Int
        let title: String?
        let originalTitle: String?
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let releaseDate: String?
        let voteAverage: Double?
        let runtime: Int?
        let genres: [Genre]?

        struct Genre: Decodable { let name: String }

        enum CodingKeys: String, CodingKey {
            case id, title, overview, runtime, genres
            case originalTitle = "original_title"
            case posterPath = "poster_path"
            case backdropPath = "backdrop_path"
            case releaseDate = "release_date"
            case voteAverage = "vote_average"
        }
    }

    /// Decode a `/search/movie` or `/search/tv` body.
    ///
    /// Rows with no usable title are dropped rather than surfaced as a blank
    /// entry the user cannot choose between. Every string is scrubbed with
    /// `MetadataSanitizer` — this is untrusted input from the internet.
    public static func parseSearchResults(
        _ data: Data,
        kind: MediaLookupType
    ) throws -> [MetadataResult] {
        let envelope: SearchEnvelope
        do {
            envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
        } catch {
            throw TMDBLookupError.malformedResponse(error.localizedDescription)
        }

        return envelope.results.compactMap { (row) -> MetadataResult? in
            let rawTitle = row.title ?? row.name
            guard let cleanTitle = sanitized(rawTitle), !cleanTitle.isEmpty else { return nil }
            let date = row.releaseDate ?? row.firstAirDate

            return MetadataResult(
                source: .tmdb,
                externalId: String(row.id),
                title: cleanTitle,
                originalTitle: sanitized(row.originalTitle ?? row.originalName),
                year: year(from: date),
                overview: sanitizedProse(row.overview),
                posterURL: row.posterPath.map { TMDBClient.posterURL(path: $0) },
                backdropURL: row.backdropPath.map { TMDBClient.posterURL(path: $0, size: "w780") },
                score: row.voteAverage,
                releaseDate: date
            )
        }
    }

    /// Decode a `/movie/{id}` body — the form that carries `runtime`.
    public static func parseMovieDetails(_ data: Data) throws -> MetadataResult {
        let envelope: DetailsEnvelope
        do {
            envelope = try JSONDecoder().decode(DetailsEnvelope.self, from: data)
        } catch {
            throw TMDBLookupError.malformedResponse(error.localizedDescription)
        }

        let cleanTitle = sanitized(envelope.title) ?? ""
        return MetadataResult(
            source: .tmdb,
            externalId: String(envelope.id),
            title: cleanTitle,
            originalTitle: sanitized(envelope.originalTitle),
            year: year(from: envelope.releaseDate),
            overview: sanitizedProse(envelope.overview),
            genres: (envelope.genres ?? []).compactMap { sanitized($0.name) },
            posterURL: envelope.posterPath.map { TMDBClient.posterURL(path: $0) },
            backdropURL: envelope.backdropPath.map { TMDBClient.posterURL(path: $0, size: "w780") },
            score: envelope.voteAverage,
            // TMDB reports 0 for "unknown", which would read as a zero-length
            // film and score terribly against a real disc. Treat it as absent.
            runtimeMinutes: (envelope.runtime ?? 0) > 0 ? envelope.runtime : nil,
            releaseDate: envelope.releaseDate
        )
    }

    /// The leading four-digit year of a TMDB date (`1999-10-15`).
    static func year(from date: String?) -> Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    /// Scrub an untrusted single-line field (a title, a genre), returning
    /// `nil` for anything blank. Same treatment `MusicBrainzDiscLookup`
    /// gives provider text — this is input from the internet (F-006).
    static func sanitized(_ text: String?) -> String? {
        guard let text else { return nil }
        let clean = MetadataSanitizer.sanitizeSingleLine(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// Scrub untrusted PROSE (an overview), which may legitimately run to
    /// several lines — so the single-line form would mangle it.
    static func sanitizedProse(_ text: String?) -> String? {
        guard let text else { return nil }
        let clean = MetadataSanitizer.sanitize(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
