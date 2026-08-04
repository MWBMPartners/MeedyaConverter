// ============================================================================
// MeedyaConverter — SFTPCredentialStore
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
#if canImport(Security)
import Security
#endif

// MARK: - SFTPCredentialStore

/// Keychain-backed store for the plaintext passwords associated with
/// saved SFTP server profiles.
///
/// **Why this exists** (SECURITY.md F-005, T4 — cloud-credential
/// exfiltration): prior to Cycle 17, `SFTPSettingsView.persistProfiles`
/// serialised the full `SFTPServerConfig` array — including the
/// plaintext password carried inside `AuthMethod.password(String)` —
/// into `~/Library/Preferences/com.mwbm.MeedyaConverter.plist`. That
/// file is world-readable for the running user, dumpable via
/// `defaults read`, and included in Time Machine / iCloud backups.
/// Effective severity HIGH because the exfiltration paths are trivial.
///
/// This store splits the persistence: the **profile metadata**
/// (host, port, username, authMethod *type*, remotePath, label,
/// profile id) lives in UserDefaults; the **credential** lives in
/// the macOS Keychain at `service = "com.mwbm.MeedyaConverter.sftp"`,
/// `account = <profile UUID>`, with the
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility
/// established in F-004.
///
/// The Keychain provides three protections the plist lacks:
/// (1) at-rest encryption keyed off the user's login password,
/// (2) per-process ACLs that prevent unrelated apps from reading
///     items that originated from a different code-signed binary,
/// (3) exclusion from iCloud Keychain sync and Time Machine backups
///     when `ThisDeviceOnly` accessibility is set.
public enum SFTPCredentialStore {

    // MARK: - Errors

    /// Errors raised by the credential-store helpers. Mostly thin
    /// wrappers around `OSStatus` from `SecItem*` so the call site
    /// can react to specific failures (e.g. `errSecItemNotFound`)
    /// rather than treating the whole Keychain as opaque.
    public enum CredentialError: Error, Equatable {
        case osStatus(OSStatus)
        case unsupportedPlatform
        case encodingFailed
    }

    // MARK: - Service name

    /// Production Keychain service name. Stable across releases —
    /// changing it would orphan every existing credential and force
    /// a manual re-entry.
    public static let productionService = "com.mwbm.MeedyaConverter.sftp"

    /// Override-able service name for tests. Production code reads
    /// `productionService`; tests set this to a unique UUID-suffixed
    /// string so they cannot collide with real Keychain entries and
    /// can be cleaned up via `deleteAll(service:)`.
    nonisolated(unsafe) public static var serviceOverride: String?

    fileprivate static var service: String {
        serviceOverride ?? productionService
    }

    // MARK: - Save

    /// Stores or overwrites the password for the profile identified
    /// by `profileID`.
    ///
    /// Empty-password storage IS allowed (some SFTP servers
    /// legitimately accept empty passwords as a "no-auth" marker);
    /// the caller is responsible for treating the empty case as
    /// invalid if it wants to.
    public static func save(password: String, forProfileID profileID: UUID) throws {
        #if canImport(Security)
        guard let data = password.data(using: .utf8) else {
            throw CredentialError.encodingFailed
        }

        // Delete-then-add for idempotent overwrite. `SecItemUpdate` is
        // awkward for single-blob payloads (it needs a separate
        // attributes dictionary), so we follow the same pattern as
        // `APIKeyManager.write` in this codebase.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
            kSecValueData as String: data,
            // `WhenUnlockedThisDeviceOnly` matches the policy set by
            // SECURITY.md F-004 — gated on currently-unlocked,
            // suppresses iCloud sync, excludes from Time Machine
            // backups. Per-profile SFTP credentials must not roam.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.osStatus(status)
        }
        #else
        throw CredentialError.unsupportedPlatform
        #endif
    }

    // MARK: - Read

    /// Returns the stored password for `profileID`, or `nil` if no
    /// Keychain entry exists. Throws on any Keychain error other
    /// than `errSecItemNotFound`.
    public static func read(forProfileID profileID: UUID) throws -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                return nil
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialError.osStatus(status)
        }
        #else
        throw CredentialError.unsupportedPlatform
        #endif
    }

    // MARK: - Delete

    /// Removes the stored password for `profileID`. Idempotent —
    /// deleting a non-existent entry is treated as success so the
    /// caller can fire this from a profile-delete flow without
    /// distinguishing already-empty from concurrent-deleted.
    public static func delete(forProfileID profileID: UUID) throws {
        #if canImport(Security)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        let status = SecItemDelete(deleteQuery as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw CredentialError.osStatus(status)
        }
        #else
        throw CredentialError.unsupportedPlatform
        #endif
    }

    /// Bulk-delete every credential under the (test-overridable)
    /// service name. Intended for unit-test teardown; production
    /// code should never call this — there is no UI flow that
    /// invalidates every saved password at once.
    public static func deleteAll(service: String) throws {
        #if canImport(Security)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(deleteQuery as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw CredentialError.osStatus(status)
        }
        #else
        throw CredentialError.unsupportedPlatform
        #endif
    }
}
