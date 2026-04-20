// ============================================================================
// MeedyaConverter — SuiteCoreTypes
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Local protocol surfaces that mirror the `meedya-core` types from the
// MeedyaSuite-core Rust workspace. Declaring them here lets the rest of the
// MeedyaConverter codebase program against a stable API whether or not the
// SUITE_CORE build flag is active.
//
// When `SUITE_CORE` is on, the `SuiteCoreAdapter` types (created in #371 and
// #372) forward calls to the real Rust implementations via the Swift bindings.
// When `SUITE_CORE` is off, the existing inline implementations
// (MetadataProviders.swift, codec detection in FFmpegProbe etc.) satisfy
// these protocols so the app still functions with a single-provider backend.
//
// GitHub Issue #373 — Add MeedyaSuite-core Swift Package dependency.
// ============================================================================

import Foundation

// MARK: - SuiteCoreMetadataProvider

/// Mirrors the `meedya-metadata::Provider` trait from MeedyaSuite-core.
public protocol SuiteCoreMetadataProvider: Sendable {
    /// Stable identifier (e.g. "tmdb", "musicbrainz") matching the suite-core
    /// provider registry keys.
    var identifier: String { get }

    /// Human-readable display name.
    var displayName: String { get }

    /// Whether this provider is currently configured with valid credentials.
    var isConfigured: Bool { get }
}

// MARK: - SuiteCoreCodecDescriptor

/// Mirrors the `meedya-codecs::AudioCodec` struct.
public struct SuiteCoreCodecDescriptor: Codable, Sendable, Hashable {
    /// Canonical codec identifier (e.g. "opus", "eac3_atmos").
    public let identifier: String
    /// Human-readable name (e.g. "Opus", "Dolby Digital Plus with Atmos").
    public let displayName: String
    /// True if this codec is lossless.
    public let isLossless: Bool
    /// True if this codec carries spatial audio metadata.
    public let isSpatial: Bool
    /// Optional channel layout hint (e.g. "7.1.4").
    public let channelLayout: String?

    public init(
        identifier: String,
        displayName: String,
        isLossless: Bool,
        isSpatial: Bool,
        channelLayout: String?
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.isLossless = isLossless
        self.isSpatial = isSpatial
        self.channelLayout = channelLayout
    }
}

// MARK: - SuiteCoreFingerprintResult

/// Mirrors the `meedya-fingerprint::FingerprintResult` type.
public struct SuiteCoreFingerprintResult: Codable, Sendable, Hashable {
    /// AcoustID-style fingerprint string.
    public let fingerprint: String
    /// Duration of the analysed audio in seconds.
    public let durationSeconds: Double

    public init(fingerprint: String, durationSeconds: Double) {
        self.fingerprint = fingerprint
        self.durationSeconds = durationSeconds
    }
}
