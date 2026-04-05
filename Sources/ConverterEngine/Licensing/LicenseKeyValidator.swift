// ============================================================================
// MeedyaConverter — License Key Validator (Stripe / Direct Distribution)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - Module Overview
// ---------------------------------------------------------------------------
// This file provides license key validation for direct-distribution builds
// where purchases flow through Stripe rather than the App Store.
//
// License key format: MC-XXXX-XXXX-XXXX-XXXX
//   - "MC" prefix identifies MeedyaConverter keys
//   - Four groups of four alphanumeric characters (uppercase A-Z, 0-9)
//   - The last group contains a Luhn-mod-36 checksum in its final character
//
// The first character after "MC-" encodes the tier:
//   - P = Plus
//   - R = Pro
//
// Activated keys are persisted in the macOS Keychain via the Security
// framework, ensuring they survive app reinstalls and are protected by
// the user's login keychain encryption.
//
// Phase 15 — Monetization / Licensing (Issue #310)
// ---------------------------------------------------------------------------

import Foundation
import Security
import CryptoKit

// ---------------------------------------------------------------------------
// MARK: - LicenseKey
// ---------------------------------------------------------------------------
/// A validated and activated license key with its associated metadata.
///
/// `LicenseKey` instances are created only after a key passes format
/// validation and tier parsing. They are persisted to the Keychain as
/// JSON so they survive app reinstalls.
// ---------------------------------------------------------------------------
public struct LicenseKey: Codable, Sendable, Equatable {

    /// The license key string in MC-XXXX-XXXX-XXXX-XXXX format.
    public let key: String

    /// The product tier this key unlocks.
    public let tier: MonetizationTier

    /// When this key was activated on this machine.
    public let activatedAt: Date

    /// When this key expires (nil for lifetime keys).
    public let expiresAt: Date?

    /// An anonymous hardware fingerprint binding the key to this machine.
    public let machineId: String

    // MARK: Computed

    /// Whether the key has expired.
    ///
    /// Lifetime keys (where `expiresAt` is `nil`) never expire.
    public var isExpired: Bool {
        guard let expiry = expiresAt else { return false }
        return Date() > expiry
    }

    /// Whether the key is currently valid (not expired).
    public var isValid: Bool {
        !isExpired
    }

    /// The entitlement level granted by this key.
    public var entitlementLevel: EntitlementLevel {
        tier.entitlementLevel
    }
}

// ---------------------------------------------------------------------------
// MARK: - LicenseKeyValidator
// ---------------------------------------------------------------------------
/// Validates license key format, parses tier information, and manages
/// Keychain persistence for activated keys.
///
/// All methods are static — no instance state is required. The validator
/// operates entirely on the local machine without network calls; server-side
/// validation (e.g., checking activation count against a Stripe webhook)
/// would be performed by a separate service layer.
///
/// ### Key Format
/// ```
/// MC-PXXX-XXXX-XXXX-XXXC
///  ^  ^                ^
///  |  |                +-- Luhn-mod-36 check character
///  |  +--- Tier indicator (P=Plus, R=Pro)
///  +------ Product prefix
/// ```
///
/// ### Keychain Storage
/// Activated keys are stored as JSON in the macOS login keychain under
/// the service name `com.mwbmpartners.meedyaconverter.license`.
// ---------------------------------------------------------------------------
public struct LicenseKeyValidator: Sendable {

    // MARK: Constants

    /// The expected prefix for all MeedyaConverter license keys.
    private static let keyPrefix = "MC"

    /// The Keychain service identifier for license storage.
    private static let keychainService = "com.mwbmpartners.meedyaconverter.license"

    /// The Keychain account name for the license entry.
    private static let keychainAccount = "activeLicense"

    /// Valid characters in key segments (uppercase alphanumeric).
    private static let validCharacterSet = CharacterSet.uppercaseLetters
        .union(.decimalDigits)

    // MARK: Validation

    /// Validate a license key string for correct format and checksum.
    ///
    /// Checks performed:
    /// 1. Matches the pattern `MC-XXXX-XXXX-XXXX-XXXX` (case-insensitive)
    /// 2. All segment characters are uppercase alphanumeric (A-Z, 0-9)
    /// 3. The Luhn-mod-36 checksum in the final character is valid
    ///
    /// - Parameter key: The license key string to validate.
    /// - Returns: `true` if the key passes all format and checksum checks.
    public static func validate(key: String) -> Bool {
        let normalised = key.uppercased().trimmingCharacters(in: .whitespaces)

        // Check overall pattern: MC-XXXX-XXXX-XXXX-XXXX
        let pattern = #"^MC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"#
        guard normalised.range(of: pattern, options: .regularExpression) != nil else {
            return false
        }

        // Extract the 16 payload characters (everything after "MC-", without dashes)
        let payload = normalised
            .replacingOccurrences(of: "MC-", with: "")
            .replacingOccurrences(of: "-", with: "")

        guard payload.count == 16 else { return false }

        // Verify Luhn-mod-36 checksum
        return verifyLuhnMod36(payload)
    }

    /// Parse the product tier encoded in a license key.
    ///
    /// The first character of the first segment (position 3 in the full key,
    /// i.e., after "MC-") indicates the tier:
    ///   - `P` = Plus
    ///   - `R` = Pro
    ///
    /// - Parameter key: The license key string.
    /// - Returns: The parsed `MonetizationTier`, or `nil` if the key format
    ///   is invalid or the tier indicator is unrecognised.
    public static func parseTier(from key: String) -> MonetizationTier? {
        let normalised = key.uppercased().trimmingCharacters(in: .whitespaces)
        guard validate(key: normalised) else { return nil }

        // The tier indicator is the first character after "MC-"
        let payload = normalised
            .replacingOccurrences(of: "MC-", with: "")
            .replacingOccurrences(of: "-", with: "")

        guard let firstChar = payload.first else { return nil }

        switch firstChar {
        case "P": return .plus
        case "R": return .pro
        default:  return nil
        }
    }

    /// Generate an anonymous hardware fingerprint for machine binding.
    ///
    /// The fingerprint is derived from the hardware UUID (IOPlatformUUID),
    /// hashed with SHA-256 to anonymise it. The result is a 16-character
    /// hex prefix — enough for collision resistance without transmitting
    /// the full hardware identifier.
    ///
    /// - Returns: A 16-character hexadecimal string derived from the hardware UUID.
    public static func generateMachineId() -> String {
        // Retrieve the hardware UUID from IOKit
        let platformExpert = IOServiceGetMatchingService(
            kIOMasterPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        defer { IOObjectRelease(platformExpert) }

        guard platformExpert != 0,
              let uuidCF = IORegistryEntryCreateCFProperty(
                  platformExpert,
                  "IOPlatformUUID" as CFString,
                  kCFAllocatorDefault,
                  0
              )?.takeRetainedValue() as? String
        else {
            // Fallback: use a stable identifier from ProcessInfo
            let hostName = ProcessInfo.processInfo.hostName
            let data = Data(hostName.utf8)
            return data.prefix(16).map { String(format: "%02x", $0) }.joined()
        }

        // Hash the UUID with SHA-256 for anonymity
        let data = Data(uuidCF.utf8)
        let digest = SHA256.hash(data: data)

        // Return the first 16 hex characters (8 bytes = 16 hex chars)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Keychain Persistence

    /// Activate a license key and persist it to the Keychain.
    ///
    /// Validates the key format and checksum, parses the tier, generates
    /// a machine ID, and stores the resulting `LicenseKey` in the macOS
    /// login keychain.
    ///
    /// - Parameter key: The license key string to activate.
    /// - Returns: The activated `LicenseKey` on success.
    /// - Throws: `LicenseKeyError` if validation fails or Keychain write fails.
    public static func activate(key: String) throws -> LicenseKey {
        let normalised = key.uppercased().trimmingCharacters(in: .whitespaces)

        guard validate(key: normalised) else {
            throw LicenseKeyError.invalidFormat
        }

        guard let tier = parseTier(from: normalised) else {
            throw LicenseKeyError.unknownTier
        }

        let license = LicenseKey(
            key: normalised,
            tier: tier,
            activatedAt: Date(),
            expiresAt: nil, // Lifetime keys do not expire
            machineId: generateMachineId()
        )

        try saveLicenseToKeychain(license)
        return license
    }

    /// Load the currently activated license from the Keychain.
    ///
    /// - Returns: The stored `LicenseKey`, or `nil` if no license is activated.
    public static func loadActiveLicense() -> LicenseKey? {
        guard let data = loadFromKeychain() else { return nil }

        do {
            let license = try JSONDecoder().decode(LicenseKey.self, from: data)
            return license
        } catch {
            return nil
        }
    }

    /// Deactivate the current license by removing it from the Keychain.
    ///
    /// - Throws: `LicenseKeyError.keychainError` if the deletion fails.
    public static func deactivate() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseKeyError.keychainError(status)
        }
    }

    // MARK: Private — Luhn-mod-36

    /// Verify a Luhn-mod-36 checksum on the given character string.
    ///
    /// The check digit is the last character in the string. Characters
    /// are mapped: 0-9 = 0-9, A-Z = 10-35.
    ///
    /// - Parameter input: The full payload string (including check character).
    /// - Returns: `true` if the checksum is valid.
    private static func verifyLuhnMod36(_ input: String) -> Bool {
        let chars = Array(input)
        guard !chars.isEmpty else { return false }

        var sum = 0
        var factor = 1 // Start with factor 1 for the check digit (rightmost)

        for char in chars.reversed() {
            guard let codePoint = codePointForCharacter(char) else { return false }

            var addend = codePoint * factor

            // Factor alternates between 1 and 2
            factor = (factor == 2) ? 1 : 2

            // Sum the digits of the addend in base 36
            addend = (addend / 36) + (addend % 36)
            sum += addend
        }

        return sum % 36 == 0
    }

    /// Map a character to its Luhn-mod-36 code point.
    ///
    /// - Parameter char: An uppercase alphanumeric character.
    /// - Returns: 0-9 for digits, 10-35 for A-Z, or `nil` for invalid characters.
    private static func codePointForCharacter(_ char: Character) -> Int? {
        if let digit = char.wholeNumberValue {
            return digit
        }
        guard let ascii = char.asciiValue, char >= "A", char <= "Z" else {
            return nil
        }
        return Int(ascii) - Int(Character("A").asciiValue!) + 10
    }

    // MARK: Private — Keychain Helpers

    /// Save a `LicenseKey` to the macOS login keychain.
    private static func saveLicenseToKeychain(_ license: LicenseKey) throws {
        let data = try JSONEncoder().encode(license)

        // Delete any existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new entry
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseKeyError.keychainError(status)
        }
    }

    /// Load raw data from the Keychain.
    private static func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }
}

// ---------------------------------------------------------------------------
// MARK: - LicenseKeyError
// ---------------------------------------------------------------------------
/// Errors from license key validation and activation.
// ---------------------------------------------------------------------------
public enum LicenseKeyError: LocalizedError, Sendable {

    /// The license key does not match the expected MC-XXXX-XXXX-XXXX-XXXX format.
    case invalidFormat

    /// The tier indicator in the key is not recognised.
    case unknownTier

    /// A Keychain operation failed with the given OSStatus code.
    case keychainError(OSStatus)

    /// The license key has expired.
    case expired

    /// The machine ID does not match the activated machine.
    case machineIdMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid license key format. Expected MC-XXXX-XXXX-XXXX-XXXX."
        case .unknownTier:
            return "The license key tier could not be determined."
        case .keychainError(let status):
            return "Keychain operation failed (OSStatus \(status))."
        case .expired:
            return "This license key has expired."
        case .machineIdMismatch:
            return "This license key is activated on a different machine."
        }
    }
}
