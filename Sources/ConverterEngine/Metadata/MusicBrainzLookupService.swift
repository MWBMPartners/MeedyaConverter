// ============================================================================
// MeedyaConverter — MusicBrainzLookupService (Issue #205, follows #493)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - MusicBrainzRequestThrottle

/// Serialises MusicBrainz requests so the process never exceeds the documented
/// ~1 request/second. Each caller is handed the next free slot BEFORE it
/// suspends, so concurrent callers get strictly spaced slots even though
/// the actor is not blocked while they sleep. Cancelling a waiting caller
/// throws `CancellationError` from `Task.sleep`; its slot stays consumed
/// (conservative — never lets a cancel produce a burst).
public actor MusicBrainzRequestThrottle {
    /// Process-wide instance every production `MusicBrainzLookupService` uses.
    /// 1.1 s rather than 1.0 s so clock jitter cannot trip the server limit.
    public static let shared = MusicBrainzRequestThrottle(minimumInterval: .milliseconds(1100))

    private let minimumInterval: Duration
    private var nextPermittedStart: ContinuousClock.Instant?

    public init(minimumInterval: Duration) {
        self.minimumInterval = minimumInterval
    }

    public func waitForTurn() async throws {
        let now = ContinuousClock.now
        let start = max(now, nextPermittedStart ?? now)
        nextPermittedStart = start + minimumInterval
        if start > now {
            try await Task.sleep(until: start, clock: .continuous)
        }
    }
}

// MARK: - MusicBrainzRecordingMatch

/// A single recording result from a MusicBrainz `/recording` search, mapped
/// from the wire JSON into a richer model than the house `MetadataResult`
/// can carry (release/artist MBIDs, the full release list, millisecond
/// length). See `metadataResult` for the lossy bridge back to `MetadataResult`.
public struct MusicBrainzRecordingMatch: Sendable, Equatable, Identifiable {

    // MARK: ArtistCredit

    public struct ArtistCredit: Sendable, Equatable {
        /// Credited name (may differ from `artist.name`, e.g. a stylisation).
        public let name: String
        /// "" when absent; e.g. " & ", " feat. ".
        public let joinPhrase: String
        /// Artist MBID.
        public let artistID: String?

        public init(name: String, joinPhrase: String = "", artistID: String? = nil) {
            self.name = name
            self.joinPhrase = joinPhrase
            self.artistID = artistID
        }
    }

    // MARK: Release

    public struct Release: Sendable, Equatable {
        /// Release MBID.
        public let id: String
        public let title: String
        /// "Official", "Bootleg", …
        public let status: String?
        /// "YYYY", "YYYY-MM" or "YYYY-MM-DD".
        public let date: String?
        public let country: String?
        /// Joined release artist-credit, nil if absent.
        public let albumArtist: String?
        public let releaseGroupID: String?
        /// "Album", "Single", …
        public let primaryType: String?
        /// "Live", "Compilation", …
        public let secondaryTypes: [String]
        /// As MusicBrainz reports it ("1", "B5").
        public let trackNumber: String?
        public let mediumPosition: Int?
        public let mediumFormat: String?
        public let mediumTrackCount: Int?

        public var trackNumberValue: Int? { trackNumber.flatMap { Int($0) } }

        public init(
            id: String,
            title: String,
            status: String? = nil,
            date: String? = nil,
            country: String? = nil,
            albumArtist: String? = nil,
            releaseGroupID: String? = nil,
            primaryType: String? = nil,
            secondaryTypes: [String] = [],
            trackNumber: String? = nil,
            mediumPosition: Int? = nil,
            mediumFormat: String? = nil,
            mediumTrackCount: Int? = nil
        ) {
            self.id = id
            self.title = title
            self.status = status
            self.date = date
            self.country = country
            self.albumArtist = albumArtist
            self.releaseGroupID = releaseGroupID
            self.primaryType = primaryType
            self.secondaryTypes = secondaryTypes
            self.trackNumber = trackNumber
            self.mediumPosition = mediumPosition
            self.mediumFormat = mediumFormat
            self.mediumTrackCount = mediumTrackCount
        }
    }

    /// Recording MBID.
    public let id: String
    public let title: String
    /// 0…100 as MusicBrainz reports it.
    public let score: Int
    public let artistCredits: [ArtistCredit]
    /// Credits joined: name+joinPhrase…; "" when no credits.
    public let artist: String
    public let lengthMilliseconds: Int?
    public let disambiguation: String?
    public let firstReleaseDate: String?
    public let releases: [Release]

    public var lengthSeconds: Double? { lengthMilliseconds.map { Double($0) / 1000 } }
    public var artistIDs: [String] { artistCredits.compactMap(\.artistID) }

    public init(
        id: String,
        title: String,
        score: Int,
        artistCredits: [ArtistCredit],
        lengthMilliseconds: Int?,
        disambiguation: String?,
        firstReleaseDate: String?,
        releases: [Release]
    ) {
        self.id = id
        self.title = title
        self.score = score
        self.artistCredits = artistCredits
        self.artist = artistCredits.map { $0.name + $0.joinPhrase }.joined()
        self.lengthMilliseconds = lengthMilliseconds
        self.disambiguation = disambiguation
        self.firstReleaseDate = firstReleaseDate
        self.releases = releases
    }

    /// The release to take album/date/track from: exact (case-insensitive)
    /// album-title match → first "Official" release whose release-group is a
    /// plain "Album" (no secondary types) → first "Official" → first listed.
    public func bestRelease(preferringAlbumTitled album: String?) -> Release? {
        if let album,
           let exact = releases.first(where: { $0.title.caseInsensitiveCompare(album) == .orderedSame }) {
            return exact
        }
        if let officialPlainAlbum = releases.first(where: {
            $0.status == "Official" && $0.primaryType == "Album" && $0.secondaryTypes.isEmpty
        }) {
            return officialPlainAlbum
        }
        if let official = releases.first(where: { $0.status == "Official" }) {
            return official
        }
        return releases.first
    }

    /// Lossy bridge to the house `MetadataResult` (no MBIDs beyond `externalId`).
    /// Used by `SuiteCoreMetadataAdapter.searchViaInline`.
    public var metadataResult: MetadataResult {
        let release = bestRelease(preferringAlbumTitled: nil)
        let dateString = release?.date ?? firstReleaseDate
        let year = dateString.flatMap { string -> Int? in
            guard string.count >= 4 else { return nil }
            return Int(string.prefix(4))
        }
        return MetadataResult(
            source: .musicBrainz,
            externalId: id,
            title: title,
            year: year,
            releaseDate: dateString,
            artist: artist,
            album: release?.title,
            trackNumber: release?.trackNumberValue,
            confidence: Double(score) / 100
        )
    }
}

// MARK: - MusicBrainzLookupError

public enum MusicBrainzLookupError: Error, Sendable, Equatable, LocalizedError {
    case emptyQuery
    case invalidURL(String)
    /// HTTP 503.
    case rateLimited(serverMessage: String?)
    /// HTTP 400 (bad Lucene query).
    case badRequest(serverMessage: String?)
    case httpStatus(statusCode: Int, bodySnippet: String)
    /// `URLError` etc., no HTTP response.
    case transport(String)
    /// 2xx but undecodable.
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter a title to search MusicBrainz."
        case .invalidURL(let url):
            return "The MusicBrainz search URL could not be formed: \(url)"
        case .rateLimited(let serverMessage):
            let base = "MusicBrainz is rate-limiting requests (HTTP 503). Wait a moment and try again."
            if let serverMessage, !serverMessage.isEmpty {
                return "\(base): \(serverMessage)"
            }
            return base
        case .badRequest(let serverMessage):
            let base = "MusicBrainz rejected the query (HTTP 400)"
            if let serverMessage, !serverMessage.isEmpty {
                return "\(base): \(serverMessage)"
            }
            return "\(base)."
        case .httpStatus(let statusCode, let bodySnippet):
            return "MusicBrainz returned HTTP \(statusCode): \(bodySnippet)"
        case .transport(let message):
            return "Could not reach MusicBrainz: \(message)"
        case .malformedResponse(let message):
            return "MusicBrainz returned a response that could not be read: \(message)"
        }
    }
}

// MARK: - MusicBrainzLookupService

public struct MusicBrainzLookupService: Sendable {
    private let httpClient: any MetadataHTTPClient
    private let throttle: MusicBrainzRequestThrottle

    public init(
        httpClient: any MetadataHTTPClient = URLSessionMetadataHTTPClient(),
        throttle: MusicBrainzRequestThrottle = .shared
    ) {
        self.httpClient = httpClient
        self.throttle = throttle
    }

    /// Search MusicBrainz recordings by title (+ optional artist).
    /// Trims both; blank title → `.emptyQuery` (no request); blank artist → no `artist:` clause.
    /// Waits for the throttle, sends via the seam, maps status → error, parses 2xx.
    /// Cancellation (Task cancel during throttle sleep or transfer) rethrows `CancellationError`.
    public func searchRecordings(title: String, artist: String?) async throws -> [MusicBrainzRecordingMatch] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw MusicBrainzLookupError.emptyQuery }
        let trimmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveArtist = (trimmedArtist?.isEmpty ?? true) ? nil : trimmedArtist
        guard let request = MusicBrainzClient.buildRecordingSearchRequest(title: trimmedTitle, artist: effectiveArtist) else {
            throw MusicBrainzLookupError.invalidURL(
                MusicBrainzClient.buildRecordingSearchURL(title: trimmedTitle, artist: effectiveArtist)
            )
        }
        try await throttle.waitForTurn()
        let result: (Data, HTTPURLResponse)
        do {
            result = try await httpClient.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MusicBrainzLookupError.transport(error.localizedDescription)
        }
        let (data, response) = result
        switch response.statusCode {
        case 200...299:
            return try Self.parseRecordingSearch(data)
        case 503:
            throw MusicBrainzLookupError.rateLimited(serverMessage: Self.serverErrorMessage(from: data))
        case 400:
            throw MusicBrainzLookupError.badRequest(serverMessage: Self.serverErrorMessage(from: data))
        default:
            throw MusicBrainzLookupError.httpStatus(statusCode: response.statusCode, bodySnippet: Self.bodySnippet(data))
        }
    }

    /// Pure decode of a `/ws/2/recording?…&fmt=json` body into matches, in server order.
    /// Recordings with no usable title are dropped; every string is passed through
    /// `MetadataSanitizer.sanitizeSingleLine` and trimmed (F-006: untrusted input).
    /// - Throws: `.malformedResponse` if the body is not the MusicBrainz envelope.
    public static func parseRecordingSearch(_ data: Data) throws -> [MusicBrainzRecordingMatch] {
        let envelope: RecordingSearchEnvelope
        do {
            envelope = try JSONDecoder().decode(RecordingSearchEnvelope.self, from: data)
        } catch {
            throw MusicBrainzLookupError.malformedResponse(error.localizedDescription)
        }
        let recordings = envelope.recordings ?? []
        return recordings.compactMap { wire -> MusicBrainzRecordingMatch? in
            guard let rawTitle = wire.title else { return nil }
            let title = sanitized(rawTitle)
            guard !title.isEmpty else { return nil }

            let artistCredits: [MusicBrainzRecordingMatch.ArtistCredit] = (wire.artistCredit ?? []).map { credit in
                MusicBrainzRecordingMatch.ArtistCredit(
                    name: sanitized(credit.name ?? ""),
                    joinPhrase: sanitizedJoinPhrase(credit.joinphrase ?? ""),
                    artistID: credit.artist?.id
                )
            }

            let releases: [MusicBrainzRecordingMatch.Release] = (wire.releases ?? []).map { wireRelease in
                let medium = wireRelease.media?.first
                let track = medium?.track?.first
                let albumArtist: String? = wireRelease.artistCredit.map { credits in
                    sanitized(credits.map { ($0.name ?? "") + ($0.joinphrase ?? "") }.joined())
                }
                return MusicBrainzRecordingMatch.Release(
                    id: wireRelease.id,
                    title: sanitized(wireRelease.title ?? ""),
                    status: wireRelease.status.map(sanitized),
                    date: wireRelease.date.map(sanitized),
                    country: wireRelease.country.map(sanitized),
                    albumArtist: albumArtist,
                    releaseGroupID: wireRelease.releaseGroup?.id,
                    primaryType: wireRelease.releaseGroup?.primaryType.map(sanitized),
                    secondaryTypes: (wireRelease.releaseGroup?.secondaryTypes ?? []).map(sanitized),
                    trackNumber: track?.number.map(sanitized),
                    mediumPosition: medium?.position,
                    mediumFormat: medium?.format.map(sanitized),
                    mediumTrackCount: medium?.trackCount
                )
            }

            return MusicBrainzRecordingMatch(
                id: wire.id,
                title: title,
                score: wire.score ?? 0,
                artistCredits: artistCredits,
                lengthMilliseconds: wire.length,
                disambiguation: wire.disambiguation.map(sanitized),
                firstReleaseDate: wire.firstReleaseDate.map(sanitized),
                releases: releases
            )
        }
    }

    /// Trims and passes a raw string through `MetadataSanitizer.sanitizeSingleLine`
    /// (untrusted input — F-006). Used for names/titles/dates where surrounding
    /// whitespace is noise.
    private static func sanitized(_ raw: String) -> String {
        MetadataSanitizer.sanitizeSingleLine(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sanitises an artist-credit join phrase (e.g. `" & "`, `" feat. "`) for
    /// control/bidi characters but PRESERVES its surrounding spaces — those
    /// spaces are the separator between credited names, so trimming them would
    /// merge names (`"Queen & David Bowie"` → `"Queen&David Bowie"`).
    /// `sanitizeSingleLine` already coalesces runs of spaces to a single space
    /// and keeps a leading/trailing single space, which is exactly right here.
    private static func sanitizedJoinPhrase(_ raw: String) -> String {
        MetadataSanitizer.sanitizeSingleLine(raw)
    }

    /// Decodes `{"error": "...", "help": "..."}` (the shape MusicBrainz uses for
    /// both HTTP 400 and 503 bodies) and sanitises the message for display/logging.
    private static func serverErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            let error: String
            let help: String?
        }
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else { return nil }
        return sanitized(envelope.error)
    }

    /// First 200 characters of the body, sanitised to a single line, for use
    /// in an error message when the server returns an unrecognised status.
    private static func bodySnippet(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        let snippet = String(text.prefix(200))
        return sanitized(snippet)
    }
}

// MARK: - Wire format (private, explicit CodingKeys for kebab-case)

private struct RecordingSearchEnvelope: Decodable {
    let recordings: [WireRecording]?
}

private struct WireRecording: Decodable {
    let id: String
    let score: Int?
    let title: String?
    let length: Int?
    let disambiguation: String?
    let artistCredit: [WireArtistCredit]?
    let firstReleaseDate: String?
    let releases: [WireRelease]?

    enum CodingKeys: String, CodingKey {
        case id, score, title, length, disambiguation, releases
        case artistCredit = "artist-credit"
        case firstReleaseDate = "first-release-date"
    }
}

private struct WireArtistCredit: Decodable {
    let name: String?
    let joinphrase: String?
    let artist: WireArtist?
}

private struct WireArtist: Decodable {
    let id: String
    let name: String?
}

private struct WireRelease: Decodable {
    let id: String
    let title: String?
    let status: String?
    let date: String?
    let country: String?
    let artistCredit: [WireArtistCredit]?
    let releaseGroup: WireReleaseGroup?
    let trackCount: Int?
    let media: [WireMedium]?

    enum CodingKeys: String, CodingKey {
        case id, title, status, date, country, media
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
        case trackCount = "track-count"
    }
}

private struct WireReleaseGroup: Decodable {
    let id: String
    let title: String?
    let primaryType: String?
    let secondaryTypes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
    }
}

private struct WireMedium: Decodable {
    let position: Int?
    let format: String?
    let track: [WireTrack]?
    let trackCount: Int?

    enum CodingKeys: String, CodingKey {
        case position, format, track
        case trackCount = "track-count"
    }
}

private struct WireTrack: Decodable {
    let id: String
    let number: String?
    let title: String?
    let length: Int?
}
