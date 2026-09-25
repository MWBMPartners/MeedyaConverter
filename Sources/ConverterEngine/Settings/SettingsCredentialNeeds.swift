// ============================================================================
// MeedyaConverter — What still needs entering after a settings import
// (Issue #506 commit 5)
// Sources/ConverterEngine/Settings/SettingsCredentialNeeds.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// A settings file never carries a password, key, token, webhook address,
// hook or consent. So after an import, MeedyaConverter tells the person what
// they still have to set up on this Mac: "TMDB key: Settings › Metadata",
// "SFTP server ‘NAS’ password: SFTP, in the main window's sidebar", and so
// on. This file works that out.
//
// Two sources of "what was set up on the other Mac":
//   - the file's `notIncluded` list: names (never values) from the fixed set
//     `SettingsLeftOutItem`, written by the exporter for each item that was
//     set up there. Without it nothing in the file could say "TMDB still
//     needs a key" (owner decision 4 in the #506 plan);
//   - the file's own SFTP server and cloud destination lists: each one that
//     signs in with a password, key file or token needs its secret here.
//
// And one question about THIS Mac for each: is it already set up here? For
// secrets, that question is answered WITHOUT READING THE SECRET:
//   - API keys (TMDB, MeedyaDB, the media server, cloud storage):
//     `APIKeyManager.hasStoredKey`, which is STATIC. An `APIKeyManager` is
//     never created here, because creating one reads every saved secret from
//     the Keychain during setup (and, over an old-format key list, rewrites
//     it). The #506 commit 2 corrections list this as a hard rule.
//   - the SMTP password: `SMTPPasswordKeychain.exists`;
//   - SFTP passwords: `SFTPCredentialStore.exists`;
//   - all three ask the Keychain only whether an item exists (see
//     `KeyPresence.swift`): the command-line tool is a different program
//     from the app, and asking for the secret data would probably make macOS
//     prompt, or refuse.
// Things kept in the settings file itself (the webhook address and headers,
// hooks, the MakeMKV and render-farm opt-ins) are checked by reading that
// setting on this Mac and asking only "is anything there?"; the value is
// never kept, logged or shown.
//
// THE APP STORE LIMIT (stated here because this is where it bites). The App
// Store build runs in a sandbox, so ITS settings and ITS list of saved keys
// (`api_keys.json`) live inside its own container folder, not in the usual
// places. The command-line tool is not sandboxed and looks in the usual
// places, so for someone who only uses the App Store build it will find no
// keys and report every one as still needed, even when the App Store app has
// them all. Nothing here tries to reach into the container: that would mean
// the command-line tool reading another app's private data. The command-line
// tool is documented as working with the Direct build only (#506 plan,
// section 6). Inside either app, everything below reads that app's own
// places and is right.
//
// "Couldn't check" is never shown as "missing": telling someone to re-type a
// key that is safely stored would be wrong. It is listed separately, with the
// reason.
// ---------------------------------------------------------------------------

import Foundation

// MARK: - SettingsLeftOutItem

/// Things that are never copied, named in a settings file's `notIncluded`
/// list when they were set up on the Mac that made the file. A closed set:
/// the file can only name these, and never carries their values.
public enum SettingsLeftOutItem: String, CaseIterable, Sendable, Codable {
    case tmdbKey
    case meedyaDBKey
    case mediaServerKey
    case smtpPassword
    case webhookAddress
    case webhookHeaders
    case hooks
    case makeMKVConsent
    case renderFarmInsecureTransport

    /// What it is, as a person would say it.
    public var displayName: String {
        switch self {
        case .tmdbKey:                     return "TMDB key"
        case .meedyaDBKey:                 return "MeedyaDB key"
        case .mediaServerKey:              return "Media server key"
        case .smtpPassword:                return "SMTP password"
        case .webhookAddress:              return "Webhook address"
        case .webhookHeaders:              return "Webhook custom headers"
        case .hooks:                       return "Hooks (actions after each encode)"
        case .makeMKVConsent:              return "MakeMKV"
        case .renderFarmInsecureTransport: return "Render farm unencrypted connections"
        }
    }

    /// Where to set it up again.
    public var location: String {
        switch self {
        case .tmdbKey:                     return "Settings › Metadata"
        case .meedyaDBKey:                 return "Settings › MeedyaDB"
        case .mediaServerKey:              return "Settings › Media Server"
        case .smtpPassword:                return "Settings › Email"
        case .webhookAddress, .webhookHeaders: return "Settings › Webhooks"
        case .hooks:                       return "Settings › Hooks"
        case .makeMKVConsent:              return "Settings › MakeMKV"
        case .renderFarmInsecureTransport: return "Settings › Render Farm"
        }
    }

    /// Why it is never copied, when that is worth saying.
    public var explanation: String? {
        switch self {
        case .tmdbKey, .meedyaDBKey, .mediaServerKey, .smtpPassword:
            return nil
        case .webhookAddress:
            return "For Slack and Discord the address works like a password, so it's never copied."
        case .webhookHeaders:
            return "They often hold a sign-in token, so they're never copied."
        case .hooks:
            return "Hooks aren't copied, because they can run commands: set them up again."
        case .makeMKVConsent:
            return "The terms have to be accepted on each Mac."
        case .renderFarmInsecureTransport:
            return "Allowing unencrypted connections has to be chosen on each Mac."
        }
    }

    /// The group whose import makes this worth mentioning: the "still
    /// needed" list only names items for groups that were actually imported.
    public var relatedCategory: SettingsCategory {
        switch self {
        case .tmdbKey, .hooks, .makeMKVConsent:
            // TMDB is used by auto-tagging, and hooks and MakeMKV belong with
            // converting and ripping: all in Encoding.
            return .encoding
        case .meedyaDBKey, .mediaServerKey, .smtpPassword, .webhookAddress, .webhookHeaders,
             .renderFarmInsecureTransport:
            return .connections
        }
    }
}

// MARK: - SettingsCredentialPresence

/// Answers "is this secret saved on this Mac?" without reading it. The
/// engine only ever asks through this protocol, so every answer is a
/// `KeyPresence`, which has no room for a secret. Tests pass a fake.
public protocol SettingsCredentialPresence: Sendable {
    /// An API key: the active entry `APIKeyManager.key(for:)` would use for
    /// `provider` (with `label`, when given) has a Keychain item.
    func apiKey(for provider: APIKeyProvider, label: String?) -> KeyPresence
    /// The SMTP (email) password.
    func smtpPassword() -> KeyPresence
    /// An SFTP server's password (filed under the server's `id`).
    func sftpPassword(forProfileID id: UUID) -> KeyPresence
    /// Whether a file exists (an SFTP key file). `~` is expanded.
    func fileExists(atPath path: String) -> Bool
}

/// The real checks, each asking the Keychain for existence only.
///
/// Never creates an `APIKeyManager` (see the file overview). The SFTP check
/// uses `SFTPCredentialStore`'s own service, which tests redirect with its
/// existing `serviceOverride`.
public struct SystemSettingsCredentialPresence: SettingsCredentialPresence {

    /// Where `api_keys.json` is; nil means this program's usual place (for a
    /// sandboxed app, inside its container — see the App Store limit in the
    /// file overview).
    let apiKeyStorageDirectory: URL?
    /// The Keychain service API keys are saved under.
    let apiKeyKeychainService: String
    /// The SMTP password's Keychain service and account.
    let smtpService: String
    let smtpAccount: String

    /// The real places, for the app and the command-line tool.
    public init(
        apiKeyStorageDirectory: URL? = nil,
        apiKeyKeychainService: String = APIKeyManager.productionKeychainService
    ) {
        self.init(
            apiKeyStorageDirectory: apiKeyStorageDirectory,
            apiKeyKeychainService: apiKeyKeychainService,
            smtpService: SMTPPasswordKeychain.service,
            smtpAccount: SMTPPasswordKeychain.account
        )
    }

    /// Test seam: the same checks against throwaway Keychain services, so
    /// tests never touch the owner's real items. Internal (reached only
    /// through `@testable import`).
    init(apiKeyStorageDirectory: URL?, apiKeyKeychainService: String, smtpService: String, smtpAccount: String) {
        self.apiKeyStorageDirectory = apiKeyStorageDirectory
        self.apiKeyKeychainService = apiKeyKeychainService
        self.smtpService = smtpService
        self.smtpAccount = smtpAccount
    }

    public func apiKey(for provider: APIKeyProvider, label: String?) -> KeyPresence {
        // STATIC on purpose: no `APIKeyManager` instance, so no secret read.
        APIKeyManager.hasStoredKey(
            for: provider,
            label: label,
            storageDirectory: apiKeyStorageDirectory,
            keychainService: apiKeyKeychainService
        )
    }

    public func smtpPassword() -> KeyPresence {
        SMTPPasswordKeychain.exists(service: smtpService, account: smtpAccount)
    }

    public func sftpPassword(forProfileID id: UUID) -> KeyPresence {
        SFTPCredentialStore.exists(forProfileID: id)
    }

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
    }
}

// MARK: - SettingsCredentialNeed

/// One thing still to set up on this Mac after an import.
public struct SettingsCredentialNeed: Sendable, Equatable {

    /// What it is.
    public enum Kind: Sendable, Equatable {
        /// One of the fixed left-out items.
        case leftOut(SettingsLeftOutItem)
        /// An imported SFTP server's password.
        case sftpPassword(profileID: UUID)
        /// An imported SFTP server's key file, which isn't on this Mac.
        case sftpKeyFile(profileID: UUID)
        /// An imported cloud destination's key or token.
        case cloudCredential(profileID: UUID)
    }

    /// Whether it is definitely missing, or could not be checked.
    public enum Status: Sendable, Equatable {
        case missing
        /// Unknown; `reason` says why (never "missing": the key may well be
        /// saved).
        case couldNotCheck(reason: String)
    }

    public let kind: Kind
    /// What it is ("TMDB key", "SFTP server ‘NAS’ password").
    public let title: String
    /// Where to set it up.
    public let location: String
    /// Why it wasn't copied, or other detail, when worth saying.
    public let explanation: String?
    public let status: Status

    /// One line for a list: "TMDB key: Settings › Metadata", with the
    /// explanation and any "couldn't check" reason after it.
    public var line: String {
        var text = "\(title): \(location)"
        if let explanation { text += ". \(explanation)" }
        if case .couldNotCheck(let reason) = status {
            text += " (Couldn't check whether it is already set up here: \(reason).)"
        }
        return text
    }
}

// MARK: - SettingsLocalSetup (is it set up on THIS Mac?)

/// Whether each left-out item is set up in `domain` / this Mac's Keychain.
/// Used by the exporter (to fill `notIncluded`) and the importer (to say
/// what is still needed), so both sides judge "set up" the same way.
enum SettingsLocalSetup {

    /// The settings (all kept in the settings file) that this file reads to
    /// answer "is anything there?". `SettingsCredentialNeedsTests` checks
    /// each is in `SettingsKeyRegistry` as "never", so a renamed key can't
    /// make this quietly answer "not set up" forever.
    static let settingsRead: [String] = [
        "webhookURL", "webhookCustomHeaders", "postEncodeActionChain",
        MediaServerCredentialStore.legacyDefaultsKey,
        MakeMKVConsentStore.Keys.enabled, MakeMKVConsentStore.Keys.termsAcknowledgement,
        RenderFarmConfigurationLoader.Keys.allowInsecureTransports,
        RenderFarmConfigurationLoader.Keys.insecureAcknowledgement,
    ]

    /// `.present` when set up, `.missing` when not, `.couldNotCheck` when a
    /// Keychain or key-list check could not answer.
    static func status(
        of item: SettingsLeftOutItem,
        domain: SettingsDomain,
        presence: any SettingsCredentialPresence
    ) -> KeyPresence {
        let defaults = domain.defaults
        switch item {
        case .tmdbKey:
            return presence.apiKey(for: .tmdb, label: nil)
        case .meedyaDBKey:
            return presence.apiKey(for: .meedyaDB, label: nil)
        case .mediaServerKey:
            // `MediaServerCredentialStore.currentKey` falls back to the old
            // plain-text value while its move to the Keychain keeps failing,
            // so that counts as set up too (only its presence is looked at).
            let keychain = presence.apiKey(for: .mediaServer, label: nil)
            if keychain == .present { return .present }
            if hasText(defaults.string(forKey: MediaServerCredentialStore.legacyDefaultsKey)) { return .present }
            return keychain
        case .smtpPassword:
            return presence.smtpPassword()
        case .webhookAddress:
            return hasText(defaults.string(forKey: "webhookURL")) ? .present : .missing
        case .webhookHeaders:
            // The screen stores "" when there are none; an empty JSON object
            // or list also means none.
            let headers = (defaults.string(forKey: "webhookCustomHeaders") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (headers.isEmpty || headers == "{}" || headers == "[]") ? .missing : .present
        case .hooks:
            // Judged the way the app judges it (`PostEncodeActionsView
            // .loadPersistedChain`): a chain that doesn't decode is treated
            // by the app as no hooks.
            guard let data = defaults.data(forKey: "postEncodeActionChain"),
                  let chain = try? JSONDecoder().decode(PostEncodeActionChain.self, from: data) else {
                return .missing
            }
            return chain.actions.isEmpty ? .missing : .present
        case .makeMKVConsent:
            return MakeMKVConsentStore.consent(in: defaults) == nil ? .missing : .present
        case .renderFarmInsecureTransport:
            let override = RenderFarmConfigurationLoader(defaults: defaults).loadConfiguration()
                .insecureTransportOverride
            return override == nil ? .missing : .present
        }
    }

    /// The items set up here, for an exported file's `notIncluded`, limited
    /// to the groups being exported. "Couldn't check" counts as set up: the
    /// importing Mac checks its own state anyway, so a name too many costs a
    /// check there, while a name too few would lose the reminder.
    static func itemsSetUp(
        domain: SettingsDomain,
        presence: any SettingsCredentialPresence,
        categories: Set<SettingsCategory>
    ) -> [SettingsLeftOutItem] {
        SettingsLeftOutItem.allCases.filter { item in
            categories.contains(item.relatedCategory)
                && status(of: item, domain: domain, presence: presence) != .missing
        }
    }

    private static func hasText(_ value: String?) -> Bool {
        !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - SettingsCredentialNeeds (after an import)

enum SettingsCredentialNeeds {

    /// Everything still to set up on this Mac, after the import has been
    /// applied to `domain`.
    ///
    /// - Parameters:
    ///   - leftOut: the known names from the file's `notIncluded`.
    ///   - appliedCategories: the groups actually imported.
    ///   - sftpServers: the imported SFTP servers AS STORED after the import
    ///     (so a password this Mac still had in its settings file, and kept,
    ///     counts as present), or nil when none were imported.
    ///   - cloudDestinations: the imported cloud destinations, or nil.
    ///
    /// See the file overview for the App Store sandbox limit that applies
    /// when the command-line tool runs this.
    static func compute(
        leftOut: [SettingsLeftOutItem],
        appliedCategories: Set<SettingsCategory>,
        sftpServers: [SFTPServerConfig]?,
        cloudDestinations: [CloudStorageConfig]?,
        domain: SettingsDomain,
        presence: any SettingsCredentialPresence
    ) -> [SettingsCredentialNeed] {
        var needs: [SettingsCredentialNeed] = []

        func add(_ kind: SettingsCredentialNeed.Kind, title: String, location: String,
                 explanation: String?, presence answer: KeyPresence) {
            switch answer {
            case .present:
                return
            case .missing:
                needs.append(SettingsCredentialNeed(
                    kind: kind, title: title, location: location, explanation: explanation, status: .missing
                ))
            case .couldNotCheck(let failure):
                needs.append(SettingsCredentialNeed(
                    kind: kind, title: title, location: location, explanation: explanation,
                    status: .couldNotCheck(reason: failure.description)
                ))
            }
        }

        // 1. The fixed items the other Mac had set up, in their fixed order.
        for item in SettingsLeftOutItem.allCases
        where leftOut.contains(item) && appliedCategories.contains(item.relatedCategory) {
            add(.leftOut(item), title: item.displayName, location: item.location,
                explanation: item.explanation,
                presence: SettingsLocalSetup.status(of: item, domain: domain, presence: presence))
        }

        let sidebar = "in the main window's sidebar"

        // 2. Each imported SFTP server that signs in with a password or key
        //    file. ("Use the SSH agent" needs nothing stored here.)
        for server in sftpServers ?? [] {
            let name = server.label.isEmpty ? server.host : server.label
            switch server.authMethod {
            case .password(let kept):
                // A password this Mac still held in its settings file was
                // kept by the import (`keepingSecrets`); only its presence
                // is looked at.
                let answer: KeyPresence = kept.isEmpty ? presence.sftpPassword(forProfileID: server.id) : .present
                add(.sftpPassword(profileID: server.id), title: "SFTP server ‘\(name)’ password",
                    location: "SFTP, \(sidebar)", explanation: nil, presence: answer)
            case .keyFile(let path):
                add(.sftpKeyFile(profileID: server.id), title: "SFTP server ‘\(name)’ key file",
                    location: "SFTP, \(sidebar)",
                    explanation: "The key file “\(path)” isn't on this Mac. Copy it here, or choose "
                        + "another key.",
                    presence: presence.fileExists(atPath: path) ? .present : .missing)
            case .agent:
                continue
            }
        }

        // 3. Each imported cloud destination's key or token. The app finds
        //    it by the destination's label first, then takes any key saved
        //    for that service (`CloudStorageProfileStore.hydrateSecrets`),
        //    so either counts.
        for destination in cloudDestinations ?? [] {
            let provider = CloudStorageProfileStore.apiKeyProvider(for: destination.provider)
            var answer = presence.apiKey(for: provider, label: destination.label)
            if answer != .present, presence.apiKey(for: provider, label: nil) == .present {
                answer = .present
            }
            let name = destination.label.isEmpty ? provider.displayName : destination.label
            add(.cloudCredential(profileID: destination.id), title: "Cloud destination ‘\(name)’ key or token",
                location: "Cloud Storage, \(sidebar)", explanation: nil, presence: answer)
        }

        return needs
    }
}
