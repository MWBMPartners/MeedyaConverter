// ============================================================================
// MeedyaConverter — MediaEncryption (Issue #351)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation
import CryptoKit

// MARK: - EncryptionMode

/// Supported AES encryption modes for media output.
///
/// Phase 13 — Encrypted Output / AES (Issue #351)
public enum EncryptionMode: String, Codable, Sendable, CaseIterable {

    /// AES-128 in CBC mode (standard HLS encryption).
    case aes128cbc

    /// AES-256 in CBC mode.
    case aes256cbc

    /// AES-128 in CTR mode (CENC / DASH common encryption).
    case aes128ctr
}

// MARK: - EncryptionConfig

/// Configuration describing how to encrypt media output.
///
/// Phase 13 — Encrypted Output / AES (Issue #351)
public struct EncryptionConfig: Codable, Sendable {

    /// The AES mode to use.
    public var mode: EncryptionMode

    /// The encryption key as a hexadecimal string.
    public var keyHex: String

    /// An optional initialisation vector as a hexadecimal string.
    /// When `nil`, a random IV is generated at encryption time.
    public var ivHex: String?

    /// Memberwise initialiser.
    public init(mode: EncryptionMode, keyHex: String, ivHex: String? = nil) {
        self.mode = mode
        self.keyHex = keyHex
        self.ivHex = ivHex
    }
}

// MARK: - MediaEncryption

/// Provides AES-based media encryption utilities for HLS packaging and
/// standalone file encryption using CryptoKit.
///
/// Phase 13 — Encrypted Output / AES (Issue #351)
public struct MediaEncryption: Sendable {

    // MARK: - Key Generation

    /// Generates a random encryption key of the specified bit length.
    ///
    /// - Parameter bits: Key size in bits (128 or 256).
    /// - Returns: A lowercase hexadecimal string representing the key.
    public static func generateKey(bits: Int) -> String {
        let byteCount = bits / 8
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Generates a random 16-byte initialisation vector.
    ///
    /// - Returns: A lowercase hexadecimal string representing the IV.
    public static func generateIV() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - HLS Key Info

    /// Builds the contents of an HLS key info file as required by FFmpeg's
    /// `-hls_key_info_file` option.
    ///
    /// Format (three lines):
    /// ```
    /// <key URL>
    /// <local key file path>
    /// <IV hex>
    /// ```
    ///
    /// - Parameters:
    ///   - keyURL: The URL from which the player will fetch the key at playback time.
    ///   - keyPath: The local file-system path where the key binary is stored.
    ///   - iv: The initialisation vector as a hexadecimal string.
    /// - Returns: The key info file contents as a single string.
    public static func buildKeyInfoFile(keyURL: String, keyPath: String, iv: String) -> String {
        return "\(keyURL)\n\(keyPath)\n\(iv)"
    }

    // MARK: - HLS Encryption Arguments

    /// Returns FFmpeg arguments for HLS AES-128 encryption.
    ///
    /// - Parameters:
    ///   - config: The encryption configuration.
    ///   - keyInfoPath: Path to the HLS key info file on disk.
    /// - Returns: An array of FFmpeg command-line argument strings.
    public static func buildHLSEncryptionArguments(
        config: EncryptionConfig,
        keyInfoPath: String
    ) -> [String] {
        return [
            "-hls_key_info_file", keyInfoPath
        ]
    }

    // MARK: - File Encryption

    /// Encrypts an entire file at `inputPath` and writes the ciphertext to `outputPath`
    /// using the AES mode specified in `config`.
    ///
    /// Uses CryptoKit's `AES.GCM` for authenticated encryption. The nonce is derived
    /// from the IV in the config (first 12 bytes) or generated randomly.
    ///
    /// - Parameters:
    ///   - inputPath: The source file path.
    ///   - outputPath: The destination file path for encrypted data.
    ///   - config: The encryption configuration (key, IV, mode).
    /// - Throws: If the file cannot be read, the key is invalid, or encryption fails.
    public static func encryptFile(
        inputPath: String,
        outputPath: String,
        config: EncryptionConfig
    ) throws {
        let plaintext = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let keyData = hexToData(config.keyHex)

        guard let key = try? makeSymmetricKey(from: keyData, bits: config.mode.keyBits) else {
            throw EncryptionError.invalidKey
        }

        let nonce: AES.GCM.Nonce
        if let ivHex = config.ivHex {
            let ivData = hexToData(ivHex)
            let nonceBytes = Array(ivData.prefix(12))
            guard nonceBytes.count == 12 else { throw EncryptionError.invalidIV }
            nonce = try AES.GCM.Nonce(data: Data(nonceBytes))
        } else {
            nonce = AES.GCM.Nonce()
        }

        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        guard let combined = sealed.combined else { throw EncryptionError.encryptionFailed }
        try combined.write(to: URL(fileURLWithPath: outputPath))
    }

    // MARK: - Private Helpers

    /// Converts a hex string to `Data`.
    private static func hexToData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }

    /// Creates a `SymmetricKey` from raw data, validating the expected bit length.
    private static func makeSymmetricKey(from data: Data, bits: Int) throws -> SymmetricKey {
        guard data.count == bits / 8 else { throw EncryptionError.invalidKey }
        return SymmetricKey(data: data)
    }
}

// MARK: - EncryptionMode + Key Bits

extension EncryptionMode {

    /// The key size in bits for this encryption mode.
    var keyBits: Int {
        switch self {
        case .aes128cbc, .aes128ctr: return 128
        case .aes256cbc:             return 256
        }
    }
}

// MARK: - EncryptionError

/// Errors raised during media encryption operations.
public enum EncryptionError: Error, LocalizedError, Sendable {
    case invalidKey
    case invalidIV
    case encryptionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidKey:        return "The encryption key is invalid or has incorrect length."
        case .invalidIV:         return "The initialisation vector is invalid."
        case .encryptionFailed:  return "AES encryption failed."
        }
    }
}
