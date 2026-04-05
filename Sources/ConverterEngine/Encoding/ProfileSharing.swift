// ============================================================================
// MeedyaConverter — ProfileSharing
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ProfileSharing

/// Utilities for exporting, importing, and sharing encoding profiles.
///
/// Supports JSON file export/import, URL-based sharing via the
/// `meedyaconverter://profile/<base64>` scheme, and profile validation.
/// All methods are static and thread-safe (value-type operations only).
public struct ProfileSharing: Sendable {

    // MARK: - URL Scheme

    /// The custom URL scheme for profile sharing links.
    private static let urlScheme = "meedyaconverter"

    /// The URL path prefix for profile share links.
    private static let profilePath = "profile"

    // MARK: - JSON Export

    /// Export an encoding profile to JSON data.
    ///
    /// The output uses pretty-printed, sorted-key formatting for readability
    /// and stable diffs.
    ///
    /// - Parameter profile: The encoding profile to export.
    /// - Returns: UTF-8 encoded JSON data representing the profile.
    /// - Throws: `EncodingError` if serialisation fails.
    public static func exportAsJSON(_ profile: EncodingProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(profile)
    }

    /// Export an encoding profile to a temporary JSON file on disk.
    ///
    /// Creates a file named `<ProfileName>.meedyaprofile.json` in the
    /// system temp directory. The caller is responsible for moving or
    /// cleaning up the file.
    ///
    /// - Parameter profile: The encoding profile to export.
    /// - Returns: The URL of the temporary JSON file.
    /// - Throws: File system or encoding errors.
    public static func exportAsURL(_ profile: EncodingProfile) throws -> URL {
        let data = try exportAsJSON(profile)
        let sanitisedName = profile.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespaces)
        let fileName = "\(sanitisedName).meedyaprofile.json"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    // MARK: - JSON Import

    /// Import an encoding profile from JSON data.
    ///
    /// The imported profile is assigned a new UUID to avoid ID collisions.
    /// The `isBuiltIn` flag is always set to `false`.
    ///
    /// - Parameter data: UTF-8 encoded JSON data of an `EncodingProfile`.
    /// - Returns: The decoded profile with a fresh UUID.
    /// - Throws: `DecodingError` if the data is invalid.
    public static func importFromJSON(_ data: Data) throws -> EncodingProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var profile = try decoder.decode(EncodingProfile.self, from: data)

        // Assign a new UUID and ensure it is not marked as built-in
        profile = EncodingProfile(
            id: UUID(),
            name: profile.name,
            description: profile.description,
            category: .custom,
            isBuiltIn: false,
            videoCodec: profile.videoCodec,
            videoPassthrough: profile.videoPassthrough,
            videoCRF: profile.videoCRF,
            videoQP: profile.videoQP,
            videoBitrate: profile.videoBitrate,
            videoMaxBitrate: profile.videoMaxBitrate,
            videoPreset: profile.videoPreset,
            videoTune: profile.videoTune,
            outputWidth: profile.outputWidth,
            outputHeight: profile.outputHeight,
            outputFrameRate: profile.outputFrameRate,
            pixelFormat: profile.pixelFormat,
            useHardwareEncoding: profile.useHardwareEncoding,
            encodingPasses: profile.encodingPasses,
            preserveHDR: profile.preserveHDR,
            toneMapToSDR: profile.toneMapToSDR,
            toneMapAlgorithm: profile.toneMapAlgorithm,
            convertPQToHLG: profile.convertPQToHLG,
            useHlgTools: profile.useHlgTools,
            toneMapPeakNits: profile.toneMapPeakNits,
            toneMapDesaturation: profile.toneMapDesaturation,
            convertPQToDVHLG: profile.convertPQToDVHLG,
            displayAspectRatio: profile.displayAspectRatio,
            audioCodec: profile.audioCodec,
            audioPassthrough: profile.audioPassthrough,
            audioBitrate: profile.audioBitrate,
            audioSampleRate: profile.audioSampleRate,
            audioChannels: profile.audioChannels,
            loudnessNormalization: profile.loudnessNormalization,
            applyPeakLimiter: profile.applyPeakLimiter,
            subtitlePassthrough: profile.subtitlePassthrough,
            perStreamSettings: profile.perStreamSettings,
            containerFormat: profile.containerFormat,
            keyframeIntervalSeconds: profile.keyframeIntervalSeconds,
            videoBufferSize: profile.videoBufferSize
        )

        return profile
    }

    /// Import an encoding profile from a JSON file on disk.
    ///
    /// - Parameter url: The file URL of a `.json` profile file.
    /// - Returns: The decoded profile with a fresh UUID.
    /// - Throws: File system or decoding errors.
    public static func importFromURL(_ url: URL) throws -> EncodingProfile {
        let data = try Data(contentsOf: url)
        return try importFromJSON(data)
    }

    // MARK: - Share Link

    /// Generate a share link for the profile using the custom URL scheme.
    ///
    /// The profile is JSON-encoded and base64url-encoded into a URL:
    /// `meedyaconverter://profile/<base64url>`.
    ///
    /// - Parameter profile: The encoding profile to share.
    /// - Returns: A URL string that can be copied to the clipboard.
    public static func generateShareLink(_ profile: EncodingProfile) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        guard let data = try? encoder.encode(profile) else {
            return "\(urlScheme)://\(profilePath)/invalid"
        }

        // Use base64url encoding (URL-safe: replace +/ with -_, remove padding)
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return "\(urlScheme)://\(profilePath)/\(base64)"
    }

    /// Decode a profile from a share link URL string.
    ///
    /// - Parameter shareLink: A `meedyaconverter://profile/<base64url>` string.
    /// - Returns: The decoded profile, or nil if the link is invalid.
    public static func importFromShareLink(_ shareLink: String) -> EncodingProfile? {
        guard let url = URL(string: shareLink),
              url.scheme == urlScheme,
              url.host == profilePath,
              let base64url = url.pathComponents.last, !base64url.isEmpty, base64url != "/" else {
            return nil
        }

        // Reverse base64url encoding
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Restore padding
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? importFromJSON(data)
    }

    // MARK: - Validation

    /// Validate an encoding profile and return any warnings.
    ///
    /// Checks for common issues such as missing codec, incompatible
    /// codec/container combinations, and missing quality settings.
    ///
    /// - Parameter profile: The encoding profile to validate.
    /// - Returns: An array of warning strings. Empty means no issues found.
    public static func validateProfile(_ profile: EncodingProfile) -> [String] {
        var warnings: [String] = []

        // Check for empty name
        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            warnings.append("Profile name is empty.")
        }

        // Check video settings
        if !profile.videoPassthrough {
            if profile.videoCodec == nil {
                warnings.append("No video codec selected. The output will have no video stream.")
            } else if let codec = profile.videoCodec {
                // Check codec/container compatibility
                if !profile.containerFormat.supportsVideoCodec(codec) {
                    warnings.append("\(codec.displayName) is not compatible with \(profile.containerFormat.displayName) container.")
                }

                // Check quality settings
                if profile.videoCRF == nil && profile.videoQP == nil && profile.videoBitrate == nil {
                    warnings.append("No quality setting (CRF, QP, or bitrate) specified for video. Output quality may be unpredictable.")
                }
            }
        }

        // Check audio settings
        if !profile.audioPassthrough {
            if let codec = profile.audioCodec {
                if !profile.containerFormat.supportsAudioCodec(codec) {
                    warnings.append("\(codec.displayName) is not compatible with \(profile.containerFormat.displayName) container.")
                }
            }
        }

        // Check HDR settings consistency
        if profile.preserveHDR && profile.toneMapToSDR {
            warnings.append("Both 'Preserve HDR' and 'Tone Map to SDR' are enabled. Tone mapping will take precedence.")
        }

        return warnings
    }

    // MARK: - Duplicate Detection

    /// Check whether a profile with the same name already exists in the store.
    ///
    /// - Parameters:
    ///   - profile: The profile to check for duplicates.
    ///   - store: The profile store to search.
    /// - Returns: `true` if a profile with the same name (case-insensitive) exists.
    public static func isDuplicate(_ profile: EncodingProfile, in store: EncodingProfileStore) -> Bool {
        store.profile(named: profile.name) != nil
    }
}
