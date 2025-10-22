// File: adaptix/core/EncryptionHandler.swift
// Purpose: Handles encryption key generation and management for HLS AES-128 encryption and basic DRM.
// Role: Creates encryption keys, key info files, and manages secure key delivery for adaptive streaming.
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation
import CryptoKit

// MARK: - Encryption Configuration

/// Configuration for content encryption
struct ContentEncryptionConfig: Codable {
    let method: EncryptionMethod
    let keyPath: String
    let keyInfoPath: String
    let keyURI: String
    let iv: String?

    enum EncryptionMethod: String, Codable {
        case aes128 = "AES-128"
        case sampleAES = "SAMPLE-AES"
        case none = "NONE"
    }
}

/// Key rotation settings for enhanced security
struct KeyRotationConfig: Codable {
    let enabled: Bool
    let intervalSegments: Int // Rotate key every N segments
    let keys: [EncryptionKey]
}

/// Represents a single encryption key
struct EncryptionKey: Codable {
    let id: String
    let keyData: Data
    let iv: Data
    let createdAt: Date
    let expiresAt: Date?
}

// MARK: - Encryption Handler

class EncryptionHandler {

    private let outputDirectory: String
    private var keyCache: [String: EncryptionKey] = [:]

    init(outputDirectory: String) {
        self.outputDirectory = outputDirectory
    }

    // MARK: - Key Generation

    /// Generates a new AES-128 encryption key
    /// - Returns: 16-byte encryption key
    func generateKey() -> Data {
        let key = SymmetricKey(size: .bits128)
        return key.withUnsafeBytes { Data($0) }
    }

    /// Generates a random initialization vector
    /// - Returns: 16-byte IV
    func generateIV() -> Data {
        var iv = Data(count: 16)
        _ = iv.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 16, bytes.baseAddress!)
        }
        return iv
    }

    /// Creates a complete encryption key with metadata
    /// - Parameters:
    ///   - expirationDays: Number of days until key expires (nil for no expiration)
    /// - Returns: EncryptionKey object
    func createEncryptionKey(expirationDays: Int? = nil) -> EncryptionKey {
        let keyData = generateKey()
        let iv = generateIV()
        let id = UUID().uuidString

        var expiresAt: Date?
        if let days = expirationDays {
            expiresAt = Calendar.current.date(byAdding: .day, value: days, to: Date())
        }

        return EncryptionKey(
            id: id,
            keyData: keyData,
            iv: iv,
            createdAt: Date(),
            expiresAt: expiresAt
        )
    }

    // MARK: - HLS Key Info File

    /// Generates HLS key info file for FFmpeg encryption
    /// - Parameters:
    ///   - key: The encryption key to use
    ///   - keyURI: URI where the key will be served (HTTP/HTTPS URL)
    ///   - outputPath: Where to save the key info file
    /// - Throws: File writing errors
    /// - Returns: Path to the key info file
    func generateHLSKeyInfo(key: EncryptionKey, keyURI: String, outputPath: String? = nil) throws -> String {
        let keyInfoPath = outputPath ?? "\(outputDirectory)/keyinfo_\(key.id).txt"
        let keyFilePath = "\(outputDirectory)/key_\(key.id).key"

        // Write the actual key file (16 bytes)
        try key.keyData.write(to: URL(fileURLWithPath: keyFilePath))

        // Create key info file format for FFmpeg:
        // Line 1: Key URI (where key will be served from)
        // Line 2: Path to key file (local path)
        // Line 3: IV (hex format, optional)
        var keyInfo = "\(keyURI)\n"
        keyInfo += "\(keyFilePath)\n"
        keyInfo += key.iv.hexString

        try keyInfo.write(toFile: keyInfoPath, atomically: true, encoding: .utf8)

        // Cache the key
        keyCache[key.id] = key

        return keyInfoPath
    }

    /// Generates FFmpeg encryption arguments for HLS
    /// - Parameters:
    ///   - keyInfoPath: Path to the key info file
    ///   - segmentDuration: Duration of each segment (default 6 seconds)
    /// - Returns: Array of FFmpeg arguments
    func generateFFmpegEncryptionArgs(keyInfoPath: String, segmentDuration: Int = 6) -> [String] {
        return [
            "-hls_key_info_file", keyInfoPath,
            "-hls_time", "\(segmentDuration)",
            "-hls_playlist_type", "vod",
            "-hls_segment_type", "mpegts"
        ]
    }

    // MARK: - Key Rotation

    /// Creates a key rotation configuration for long-form content
    /// - Parameters:
    ///   - intervalSegments: Rotate key every N segments
    ///   - numberOfKeys: Total number of keys to generate
    /// - Returns: KeyRotationConfig with pre-generated keys
    func createKeyRotation(intervalSegments: Int = 10, numberOfKeys: Int = 5) -> KeyRotationConfig {
        var keys: [EncryptionKey] = []

        for _ in 0..<numberOfKeys {
            keys.append(createEncryptionKey(expirationDays: 30))
        }

        return KeyRotationConfig(
            enabled: true,
            intervalSegments: intervalSegments,
            keys: keys
        )
    }

    // MARK: - Key Management

    /// Saves encryption key to disk (encrypted with keychain password)
    /// - Parameters:
    ///   - key: The encryption key to save
    ///   - path: File path to save to
    /// - Throws: Encoding or file writing errors
    func saveKey(_ key: EncryptionKey, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(key)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Loads encryption key from disk
    /// - Parameter path: Path to the key file
    /// - Returns: Loaded EncryptionKey
    /// - Throws: Decoding or file reading errors
    func loadKey(from path: String) throws -> EncryptionKey {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        return try decoder.decode(EncryptionKey.self, from: data)
    }

    /// Retrieves a cached key by ID
    /// - Parameter id: The key ID
    /// - Returns: EncryptionKey if found, nil otherwise
    func getCachedKey(id: String) -> EncryptionKey? {
        return keyCache[id]
    }

    /// Checks if a key has expired
    /// - Parameter key: The key to check
    /// - Returns: true if expired, false otherwise
    func isKeyExpired(_ key: EncryptionKey) -> Bool {
        guard let expiresAt = key.expiresAt else {
            return false // No expiration
        }
        return Date() > expiresAt
    }

    /// Cleans up expired keys from cache and disk
    /// - Throws: File deletion errors
    func cleanupExpiredKeys() throws {
        let expiredKeys = keyCache.filter { isKeyExpired($0.value) }

        for (id, _) in expiredKeys {
            // Remove from cache
            keyCache.removeValue(forKey: id)

            // Remove key file
            let keyFilePath = "\(outputDirectory)/key_\(id).key"
            if FileManager.default.fileExists(atPath: keyFilePath) {
                try FileManager.default.removeItem(atPath: keyFilePath)
            }

            // Remove key info file
            let keyInfoPath = "\(outputDirectory)/keyinfo_\(id).txt"
            if FileManager.default.fileExists(atPath: keyInfoPath) {
                try FileManager.default.removeItem(atPath: keyInfoPath)
            }
        }
    }

    // MARK: - Simple Key Server

    /// Generates a simple key delivery manifest for testing
    /// This is NOT production-ready and should be replaced with proper DRM/CDN
    /// - Parameters:
    ///   - key: The encryption key
    ///   - baseURL: Base URL where keys will be served
    /// - Returns: ContentEncryptionConfig for use in encoding
    func generateSimpleKeyDelivery(key: EncryptionKey, baseURL: String) throws -> ContentEncryptionConfig {
        let keyFileName = "key_\(key.id).key"
        let keyPath = "\(outputDirectory)/\(keyFileName)"
        let keyInfoPath = "\(outputDirectory)/keyinfo_\(key.id).txt"
        let keyURI = "\(baseURL)/keys/\(keyFileName)"

        // Write key file
        try key.keyData.write(to: URL(fileURLWithPath: keyPath))

        return ContentEncryptionConfig(
            method: .aes128,
            keyPath: keyPath,
            keyInfoPath: keyInfoPath,
            keyURI: keyURI,
            iv: key.iv.hexString
        )
    }

    // MARK: - Validation

    /// Validates an encryption key
    /// - Parameter key: The key to validate
    /// - Returns: true if valid, false otherwise
    func validateKey(_ key: EncryptionKey) -> Bool {
        // Check key size (must be 16 bytes for AES-128)
        guard key.keyData.count == 16 else {
            return false
        }

        // Check IV size (must be 16 bytes)
        guard key.iv.count == 16 else {
            return false
        }

        // Check if expired
        if isKeyExpired(key) {
            return false
        }

        return true
    }

    /// Generates a README for key deployment
    /// - Parameter config: The encryption configuration
    /// - Returns: Markdown formatted instructions
    func generateKeyDeploymentInstructions(config: ContentEncryptionConfig) -> String {
        return """
        # Encryption Key Deployment Instructions

        ## Configuration
        - **Method**: \(config.method.rawValue)
        - **Key URI**: \(config.keyURI)
        - **IV**: \(config.iv ?? "Embedded in segments")

        ## Deployment Steps

        ### 1. Upload Encryption Key
        Upload the key file to your web server or CDN:
        ```
        Source: \(config.keyPath)
        Destination: \(config.keyURI)
        ```

        ### 2. Configure Web Server
        Ensure your web server serves the key file with proper CORS headers:
        ```
        Access-Control-Allow-Origin: *
        Access-Control-Allow-Methods: GET, OPTIONS
        Access-Control-Allow-Headers: *
        ```

        ### 3. Secure the Key (Recommended)
        - Use HTTPS for all key delivery
        - Implement token-based authentication
        - Add IP whitelisting if possible
        - Consider using a proper DRM solution for production

        ### 4. Test Key Delivery
        Test that the key is accessible:
        ```bash
        curl -I \(config.keyURI)
        ```

        ## Security Notice
        This is a basic encryption implementation suitable for:
        - Internal content
        - Low-value content
        - Testing and development

        For production use with valuable content, consider:
        - FairPlay DRM (Apple)
        - Widevine DRM (Google)
        - PlayReady DRM (Microsoft)
        - Commercial DRM services (BuyDRM, Irdeto, etc.)

        ## Generated on: \(Date())
        """
    }
}

// MARK: - Extensions

extension Data {
    /// Converts Data to hexadecimal string
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Creates Data from hexadecimal string
    init?(hexString: String) {
        let length = hexString.count / 2
        var data = Data(capacity: length)
        var index = hexString.startIndex

        for _ in 0..<length {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}

// MARK: - Errors

enum EncryptionError: Error, LocalizedError {
    case keyGenerationFailed
    case invalidKeySize
    case keyExpired
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        case .invalidKeySize:
            return "Invalid key size (must be 16 bytes for AES-128)"
        case .keyExpired:
            return "Encryption key has expired"
        case .fileWriteFailed(let message):
            return "Failed to write key file: \(message)"
        }
    }
}
