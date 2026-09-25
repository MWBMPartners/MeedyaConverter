// ============================================================================
// MeedyaConverter — KeyPresence (Issue #506 commit 2)
// Sources/ConverterEngine/Cloud/KeyPresence.swift
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Answers ONE question — "is a password or key saved for this?" — without
// ever reading the password or key itself.
//
// Why this exists (#506, settings export/import): after someone imports a
// settings file, MeedyaConverter tells them which passwords and keys they
// still need to type in on this Mac ("TMDB still needs a key"). That check
// runs in the app AND in the command-line tool (`meedya-convert`), and the
// command-line tool is a DIFFERENT PROGRAM from the app. macOS protects each
// saved secret so that only the program that saved it can read it without
// asking. If the command-line tool asked the Keychain for the secret DATA of
// an item the app saved, macOS would probably show a "meedya-convert wants
// to use your confidential information" prompt — or simply refuse. Asking
// only whether a matching item EXISTS needs none of that protected data, so
// it is designed not to prompt. (That design goal cannot be proven by an
// automated test; it needs one manual run of the command-line tool against a
// key the app saved. See the #506 plan, section 9, "Risks".)
//
// Three places keep secrets in the Keychain, and all three ask through the
// one query builder below (`KeychainItemExistence.query`), so there is
// exactly one place where "attributes only" is decided and one place a test
// checks it:
//   - `APIKeyManager.hasStoredKey(for:label:…)` — TMDB, MeedyaDB, the media
//     server, cloud storage, and the other API-key providers;
//   - `SFTPCredentialStore.exists(forProfileID:)` — SFTP passwords;
//   - `SMTPPasswordKeychain.exists()` — the email (SMTP) password.
//
// WHAT A "PRESENT" ANSWER CANNOT PROVE: only that a Keychain item with the
// right name exists. It says nothing about whether the secret inside is
// correct, still accepted by the service, not expired, or even readable by
// the program that will later need it. Checking any of that would mean
// reading the secret, which is exactly what this file exists to avoid.
// ---------------------------------------------------------------------------

import Foundation

// The Security framework provides `SecItemCopyMatching`. On builds without
// it (any non-Apple platform) there is no Keychain to ask, and every check
// answers "couldn't check" rather than guessing.
#if canImport(Security)
import Security
#endif

// MARK: - KeyPresence

/// Whether a password or key is saved, found WITHOUT reading it.
///
/// **Why three answers and not a `Bool`.** A `Bool` has only two values, so
/// "we couldn't find out" would have to be squeezed into one of them — and
/// the natural place for it (`false`) says "nothing is saved". That would
/// tell someone to re-type a key that is actually safely stored, just
/// because the saved-keys list was briefly unreadable. A separate "couldn't
/// check" signal next to a `Bool` has the same weakness in practice: the
/// easy code (`if !hasKey`) ignores it. With an enum, every `switch` over it
/// has to decide what "couldn't check" means, and the compiler insists.
///
/// No case carries the secret, or any part of it — the checks that produce
/// this value never have the secret to hand in the first place.
public enum KeyPresence: Equatable, Sendable, CustomStringConvertible {

    /// A matching Keychain item exists (and, for API keys, an active entry
    /// in the saved-keys list points at it). This does NOT prove the secret
    /// is correct or still accepted — see the file overview.
    case present

    /// Definitely nothing usable is saved: no saved-keys list at all, no
    /// active entry for this service in it, or the Keychain answered "no
    /// such item".
    case missing

    /// The answer could not be found out. Never treat this as `.missing`:
    /// the key may well be saved. The associated value says why, in terms
    /// safe to show or log (it never contains a secret).
    case couldNotCheck(KeyPresenceCheckFailure)

    /// Plain-English wording, safe to log: it names the state only.
    public var description: String {
        switch self {
        case .present:
            return "saved"
        case .missing:
            return "not saved"
        case .couldNotCheck(let failure):
            return "couldn't check: \(failure.description)"
        }
    }
}

// MARK: - KeyPresenceCheckFailure

/// Why a presence check could not give a definite answer.
public enum KeyPresenceCheckFailure: Equatable, Sendable, CustomStringConvertible {

    /// The saved-keys list (`api_keys.json`) exists but could not be read
    /// from disk — for example a permissions problem, or something that is
    /// not a file sitting where the file should be.
    case indexUnreadable

    /// The saved-keys list was read but is not in the format this version
    /// writes. That covers three different situations, deliberately not
    /// told apart here (telling them apart would mean digging further into
    /// a file that may hold plain-text secrets from an old version):
    ///   - it is damaged;
    ///   - it is still in the pre-Keychain format from an old version,
    ///     which MeedyaConverter converts the next time it opens the list;
    ///   - it was written by a NEWER version that knows a service this one
    ///     doesn't.
    case indexNotRecognised

    /// The Keychain answered with an error instead of "found" or "not
    /// found" — for example because macOS refused this program, or would
    /// have needed to ask the user something it isn't allowed to. `status`
    /// is the raw `OSStatus` code (kept as `Int32` so this public type
    /// compiles on platforms without the Security framework's `OSStatus`
    /// typealias).
    case keychainRefused(status: Int32)

    /// This build has no Keychain to ask (a non-Apple platform).
    case keychainUnavailable

    /// Plain-English wording, safe to log.
    public var description: String {
        switch self {
        case .indexUnreadable:
            return "the list of saved keys could not be read"
        case .indexNotRecognised:
            return "the list of saved keys is not in a format this version understands"
        case .keychainRefused(let status):
            return "the Keychain did not answer (error \(status))"
        case .keychainUnavailable:
            return "there is no Keychain on this platform"
        }
    }
}

// MARK: - KeychainItemExistence

/// The one attributes-only Keychain question every presence check asks.
///
/// Internal, not public: the three store types above wrap it with their own
/// service and account names, and a test (`KeyPresenceTests`) inspects
/// `query(service:account:)` directly to prove it never asks for the
/// secret.
enum KeychainItemExistence {

    #if canImport(Security)
    /// Builds the `SecItemCopyMatching` query for "does a generic-password
    /// item with this service and account exist?".
    ///
    /// **What is deliberately NOT in it:**
    /// - `kSecReturnData` — that is the secret itself. Asking for it is
    ///   what would make macOS prompt (or refuse) when the program asking
    ///   is not the one that saved the item.
    /// - `kSecReturnAttributes`, `kSecReturnRef`, `kSecReturnPersistentRef`
    ///   — not needed. Apple's `SecItem.h` says "If a result type is not
    ///   specified, no results are returned": with none of the four return
    ///   keys, `SecItemCopyMatching` only reports found (`errSecSuccess`)
    ///   or not found (`errSecItemNotFound`). Leaving them all out is the
    ///   most that can be left out.
    /// - `kSecAttrAccessible` — items saved before SECURITY.md F-004 (the
    ///   SMTP password in particular) were stored without it, so matching
    ///   on it would wrongly report them as missing.
    ///
    /// `kSecMatchLimitOne` stops the search at the first match — one is all
    /// "does it exist?" needs.
    static func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
    }
    #endif

    /// Asks the Keychain whether the item exists, using only
    /// `query(service:account:)` above.
    ///
    /// The result pointer passed to `SecItemCopyMatching` is `nil`: no
    /// return type is requested, so there is nothing to receive, and this
    /// function has no way to hand a secret back even if the query were
    /// ever changed by mistake. (That is a second line of defence, not the
    /// first: a query that ASKED for the data could still trigger a prompt
    /// before the result was thrown away. The first line is the query, and
    /// `KeyPresenceTests` checks it.)
    static func check(service: String, account: String) -> KeyPresence {
        #if canImport(Security)
        let status = SecItemCopyMatching(query(service: service, account: account) as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return .present
        case errSecItemNotFound:
            return .missing
        default:
            // Anything else (for example `errSecInteractionNotAllowed`, or
            // an access refusal) is "couldn't check", never "missing". None
            // of these error paths is exercised by a test: the real Keychain
            // can't be made to produce them on demand.
            return .couldNotCheck(.keychainRefused(status: status))
        }
        #else
        return .couldNotCheck(.keychainUnavailable)
        #endif
    }
}
