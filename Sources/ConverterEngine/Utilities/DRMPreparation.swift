// ============================================================================
// MeedyaConverter — DRMPreparation (Issue #352)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DRMSystem

/// Supported Digital Rights Management systems for content protection.
///
/// Phase 13 — DRM Preparation / CPIX / PSSH (Issue #352)
public enum DRMSystem: String, Codable, Sendable, CaseIterable {

    /// Google Widevine — the most widely deployed DRM on Android, Chrome, and smart TVs.
    case widevine

    /// Apple FairPlay Streaming — used on Safari, iOS, tvOS, and macOS.
    case fairplay

    /// Microsoft PlayReady — used on Edge, Xbox, and many smart-TV platforms.
    case playready
}

// MARK: - DRMConfig

/// Configuration for multi-DRM content protection packaging.
///
/// Phase 13 — DRM Preparation / CPIX / PSSH (Issue #352)
public struct DRMConfig: Codable, Sendable {

    /// The DRM systems to target.
    public var systems: [DRMSystem]

    /// The key ID as a hexadecimal or UUID-formatted string.
    public var keyId: String

    /// The content encryption key as a hexadecimal string.
    public var contentKey: String

    /// The license-server URL used by player SDKs to request decryption keys.
    public var licenseServerURL: String?

    /// Memberwise initialiser.
    public init(
        systems: [DRMSystem],
        keyId: String,
        contentKey: String,
        licenseServerURL: String? = nil
    ) {
        self.systems = systems
        self.keyId = keyId
        self.contentKey = contentKey
        self.licenseServerURL = licenseServerURL
    }
}

// MARK: - DRMPreparation

/// Generates PSSH boxes, CPIX documents, and FFmpeg arguments for
/// multi-DRM content preparation.
///
/// Phase 13 — DRM Preparation / CPIX / PSSH (Issue #352)
public struct DRMPreparation: Sendable {

    // MARK: - System IDs

    /// The standard Widevine system ID UUID (edef8ba9-79d6-4ace-a3c8-27dcd51d21ed).
    public static func widevineSystemId() -> String {
        return "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"
    }

    /// The standard PlayReady system ID UUID (9a04f079-9840-4286-ab92-e65be0885f95).
    public static func playreadySystemId() -> String {
        return "9a04f079-9840-4286-ab92-e65be0885f95"
    }

    /// Returns the standard system ID UUID string for the given DRM system.
    ///
    /// - Parameter system: The DRM system.
    /// - Returns: The system ID as a lowercase UUID string.
    public static func systemId(for system: DRMSystem) -> String {
        switch system {
        case .widevine:  return widevineSystemId()
        case .playready: return playreadySystemId()
        case .fairplay:  return "94ce86fb-07ff-4f43-adb8-93d2fa968ca2"
        }
    }

    // MARK: - PSSH Box Generation

    /// Generates a binary PSSH (Protection System Specific Header) box for the
    /// specified DRM system and key ID.
    ///
    /// The PSSH box follows the ISO BMFF box format:
    /// - 4 bytes: box size (big-endian)
    /// - 4 bytes: box type ("pssh")
    /// - 1 byte:  version (0)
    /// - 3 bytes: flags (0x000000)
    /// - 16 bytes: system ID
    /// - 4 bytes: data size (big-endian)
    /// - N bytes: system-specific data (key ID)
    ///
    /// - Parameters:
    ///   - system: The DRM system for which to generate the PSSH box.
    ///   - keyId: The key ID as a 32-character hexadecimal string.
    /// - Returns: The binary PSSH box as `Data`.
    public static func generatePSSHBox(system: DRMSystem, keyId: String) -> Data {
        let systemIdBytes = uuidStringToBytes(systemId(for: system))
        let keyIdBytes = hexStringToBytes(keyId)

        var psshData = Data()

        // For Widevine, the PSSH data payload wraps the key ID in a simple
        // protobuf-like structure: field 2 (bytes), wire type 2.
        let payload: Data
        switch system {
        case .widevine:
            // Widevine PSSH data: 0x12 (field 2, wire type 2), length, key ID bytes
            var wvPayload = Data()
            wvPayload.append(0x12) // field tag
            wvPayload.append(UInt8(keyIdBytes.count)) // length
            wvPayload.append(contentsOf: keyIdBytes)
            payload = wvPayload
        case .playready, .fairplay:
            // Generic: key ID as raw bytes.
            payload = Data(keyIdBytes)
        }

        // Calculate total box size: header(8) + version/flags(4) + systemID(16) + dataSize(4) + payload
        let totalSize = UInt32(8 + 4 + 16 + 4 + payload.count)

        // Box size (big-endian).
        withUnsafeBytes(of: totalSize.bigEndian) { psshData.append(contentsOf: $0) }

        // Box type "pssh".
        psshData.append(contentsOf: [0x70, 0x73, 0x73, 0x68]) // "pssh" in ASCII

        // Version (0) and flags (0x000000).
        psshData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // System ID (16 bytes).
        psshData.append(contentsOf: systemIdBytes)

        // Data size (big-endian).
        let dataSize = UInt32(payload.count)
        withUnsafeBytes(of: dataSize.bigEndian) { psshData.append(contentsOf: $0) }

        // Payload.
        psshData.append(payload)

        return psshData
    }

    // MARK: - CPIX Document

    /// Generates a CPIX (Content Protection Information Exchange) XML document
    /// describing the DRM configuration for multi-DRM packaging workflows.
    ///
    /// - Parameter config: The DRM configuration.
    /// - Returns: A CPIX 2.3 XML string.
    public static func generateCPIXDocument(config: DRMConfig) -> String {
        let systemElements = config.systems.map { system -> String in
            let sysId = systemId(for: system)
            let psshBase64 = generatePSSHBox(system: system, keyId: config.keyId)
                .base64EncodedString()
            return """
                <DRMSystem kid="\(config.keyId)" systemId="\(sysId)">
                    <PSSH>\(psshBase64)</PSSH>
                </DRMSystem>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <CPIX xmlns="urn:dashif:org:cpix" xmlns:pskc="urn:ietf:params:xml:ns:keyprov:pskc"
              id="\(UUID().uuidString)">
            <ContentKeyList>
                <ContentKey kid="\(config.keyId)">
                    <Data>
                        <pskc:Secret>
                            <pskc:PlainValue>\(Data(hexStringToBytes(config.contentKey)).base64EncodedString())</pskc:PlainValue>
                        </pskc:Secret>
                    </Data>
                </ContentKey>
            </ContentKeyList>
            <DRMSystemList>
        \(systemElements)
            </DRMSystemList>
        </CPIX>
        """
    }

    // MARK: - FFmpeg Arguments

    /// Builds FFmpeg command-line arguments for DRM-prepared packaging.
    ///
    /// Generates `-encryption_scheme`, `-encryption_key`, `-encryption_kid` arguments
    /// suitable for DASH/CENC packaging with FFmpeg.
    ///
    /// - Parameter config: The DRM configuration.
    /// - Returns: An array of FFmpeg argument strings.
    public static func buildDRMArguments(config: DRMConfig) -> [String] {
        var args: [String] = []

        // CENC encryption scheme (cenc = AES-CTR, cbcs = AES-CBC sample).
        args.append(contentsOf: ["-encryption_scheme", "cenc-aes-ctr"])

        // Content encryption key.
        args.append(contentsOf: ["-encryption_key", config.contentKey])

        // Key ID.
        args.append(contentsOf: ["-encryption_kid", config.keyId])

        return args
    }

    // MARK: - Private Helpers

    /// Converts a UUID string (with or without hyphens) to a 16-byte array.
    private static func uuidStringToBytes(_ uuidString: String) -> [UInt8] {
        let hex = uuidString.replacingOccurrences(of: "-", with: "")
        return hexStringToBytes(hex)
    }

    /// Converts a hexadecimal string to a byte array.
    private static func hexStringToBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return bytes
    }
}
