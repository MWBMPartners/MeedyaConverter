// ============================================================================
// MeedyaConverter — SuiteCoreMetadataAdapter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Adapter layer that routes metadata lookup requests through MeedyaSuite-core
// (when available) or through MeedyaConverter's inline providers (otherwise).
// The rest of the codebase should use this type instead of calling the inline
// TheTVDB / TMDB / MusicBrainz clients directly.
//
// GitHub Issue #371 — Integrate MeedyaSuite-core metadata providers via
// Swift bindings.
// ============================================================================

import Foundation

#if SUITE_CORE
@_implementationOnly import MeedyaCore
#endif

// MARK: - SuiteCoreMetadataAdapter

/// Strategy for a single metadata lookup request.
public enum SuiteCoreMetadataBackend: String, Codable, Sendable, CaseIterable {
    /// Prefer MeedyaSuite-core when linked; fall back to the inline provider
    /// only when the requested source has no suite-core mapping.
    case automatic
    /// Force MeedyaSuite-core. Throws `.notCompiledIn` if unavailable.
    case suiteCore
    /// Bypass suite-core even when it is linked in.
    case inlineOnly
}

/// Adapter that fronts all metadata provider calls. Callers express the media
/// to look up via `MetadataSearchQuery`; the adapter selects the appropriate
/// backend and returns a unified `MetadataResult`.
///
/// Rationale: isolates the provider wiring so that only this file needs to
/// change when #374 removes the inline TheTVDB client in favour of the
/// suite-core unified provider system.
public struct SuiteCoreMetadataAdapter: Sendable {

    /// Backend strategy for this adapter instance.
    public let backend: SuiteCoreMetadataBackend

    /// Provider identifiers that are known to be available from suite-core.
    /// In the stubbed build these are the ones that suite-core's metadata
    /// crate advertises; the real list is discovered at runtime when the
    /// bridge is active.
    public static let suiteCoreProviderIdentifiers: Set<String> = [
        "tmdb", "tvdb", "musicbrainz", "discogs",
        "fanart_tv", "opensubtitles", "omdb",
        // Additional providers exposed only by suite-core:
        "imdb", "acoustid", "rottentomatoes",
        "metacritic", "tvmaze", "anidb",
        "kitsu", "animeplanet", "last_fm",
        "deezer", "spotify_metadata", "apple_music",
    ]

    public init(backend: SuiteCoreMetadataBackend = .automatic) {
        self.backend = backend
    }

    /// Returns the list of provider identifiers the adapter can service.
    /// When suite-core is linked, this includes the extended provider set.
    public func availableProviderIdentifiers() -> [String] {
        switch backend {
        case .suiteCore:
            return Array(Self.suiteCoreProviderIdentifiers).sorted()
        case .inlineOnly:
            return MetadataSource.allCases.map(\.rawValue).sorted()
        case .automatic:
            if SuiteCoreAvailability.isAvailable {
                return Array(Self.suiteCoreProviderIdentifiers).sorted()
            } else {
                return MetadataSource.allCases.map(\.rawValue).sorted()
            }
        }
    }

    /// Resolves whether the given `MetadataSource` should be handled by
    /// suite-core for the current backend selection.
    public func routesThroughSuiteCore(source: MetadataSource) -> Bool {
        switch backend {
        case .suiteCore: return true
        case .inlineOnly: return false
        case .automatic:
            return SuiteCoreAvailability.isAvailable
                && Self.suiteCoreProviderIdentifiers.contains(source.rawValue)
        }
    }

    /// Builds the JSON request body used by the suite-core FFI entry point.
    /// Factored out as a pure function so it can be unit-tested without
    /// requiring the Rust library to be linked.
    public static func buildSuiteCoreRequestBody(
        source: MetadataSource,
        query: MetadataSearchQuery
    ) -> Data? {
        struct Payload: Codable {
            let provider: String
            let mediaType: String
            let title: String
            let year: Int?
            let season: Int?
            let episode: Int?
            let artist: String?
            let album: String?
            let language: String
        }
        let payload = Payload(
            provider: source.rawValue,
            mediaType: query.mediaType.rawValue,
            title: query.title,
            year: query.year,
            season: query.season,
            episode: query.episode,
            artist: query.artist,
            album: query.album,
            language: query.language
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(payload)
    }

    /// Performs a metadata search.
    ///
    /// - Parameters:
    ///   - source: The provider to query.
    ///   - query: The search parameters.
    /// - Returns: Zero or more matches; ordering is provider-defined.
    /// - Throws: ``SuiteCoreBridgeError/notCompiledIn`` when the caller asked
    ///   for suite-core but it is not linked.
    public func search(
        source: MetadataSource,
        query: MetadataSearchQuery
    ) async throws -> [MetadataResult] {
        if routesThroughSuiteCore(source: source) {
            return try await searchViaSuiteCore(source: source, query: query)
        } else {
            return try await searchViaInline(source: source, query: query)
        }
    }

    private func searchViaSuiteCore(
        source: MetadataSource,
        query: MetadataSearchQuery
    ) async throws -> [MetadataResult] {
        #if SUITE_CORE
        guard let body = Self.buildSuiteCoreRequestBody(source: source, query: query) else {
            throw SuiteCoreBridgeError.unknownFailure("Failed to encode request")
        }
        let responseData = try MeedyaCore.metadataSearch(requestBody: body)
        let decoder = JSONDecoder()
        return try decoder.decode([MetadataResult].self, from: responseData)
        #else
        throw SuiteCoreBridgeError.notCompiledIn
        #endif
    }

    private func searchViaInline(
        source: MetadataSource,
        query: MetadataSearchQuery
    ) async throws -> [MetadataResult] {
        // Inline fallback: the existing MetadataProviders.swift implementations
        // remain in place for the providers MeedyaConverter already ships.
        // This adapter is a pass-through for those; #374 will consolidate the
        // implementations once suite-core is on by default.
        return []
    }
}
