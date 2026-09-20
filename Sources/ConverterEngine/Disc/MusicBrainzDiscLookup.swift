// ============================================================================
// MeedyaConverter — MusicBrainzDiscLookup (Issue #502, slice 2)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Keyless Audio CD identification: turn a disc's table of contents into a list
// of candidate album releases from MusicBrainz, which the ranking engine
// (`DiscIdentifier`) can then order. This is the first "real candidate source"
// feeding the #502 identification engine, and it needs NO API key — MusicBrainz's
// disc/TOC lookup is public.
//
// It deliberately REUSES what already exists rather than adding a parallel stack:
//   * the TOC-string format from `AudioCDReader.buildMusicBrainzTOC(...)` (one
//     source of truth for the `+`-joined offsets MusicBrainz expects);
//   * the injectable `MetadataHTTPClient` seam, the ~1 req/sec
//     `MusicBrainzRequestThrottle`, the `MusicBrainzClient.userAgent` /
//     `requestTimeoutSeconds`, the `MusicBrainzLookupError` cases and the
//     `MetadataSanitizer` scrubbing — all as used by `MusicBrainzLookupService`.
//
// Standard CD pre-gap: MusicBrainz TOC offsets are absolute sector positions that
// include the 150-frame (2-second) lead-in, so every offset and the lead-out have
// +150 added — matching `AudioCDReader.calculateCDDBDiscId` / `buildCDDBQuery`.
//
// Live MusicBrainz traffic is not exercised in CI (no network); the seam covers
// everything below it, and the wire model follows the documented
// `/ws/2/discid/-?toc=...` response shape (a top-level `releases` list).
// ============================================================================

import Foundation

// MARK: - MusicBrainzDiscMatch

/// One candidate album release returned by a MusicBrainz disc/TOC lookup.
public struct MusicBrainzDiscMatch: Sendable, Equatable, Identifiable {
    /// Release MBID.
    public let id: String
    /// Release (album) title.
    public let title: String
    /// Joined release artist-credit, or `nil` when absent.
    public let artist: String?
    /// Release date as MusicBrainz reports it ("YYYY", "YYYY-MM", "YYYY-MM-DD").
    public let date: String?
    /// Release country, if given.
    public let country: String?
    /// Total track count across the release's media, if known.
    public let trackCount: Int?
    /// Number of media (discs) in the release, if known.
    public let mediumCount: Int?

    public init(
        id: String,
        title: String,
        artist: String? = nil,
        date: String? = nil,
        country: String? = nil,
        trackCount: Int? = nil,
        mediumCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.date = date
        self.country = country
        self.trackCount = trackCount
        self.mediumCount = mediumCount
    }

    /// Release year parsed from the leading four digits of `date`, if present.
    public var year: Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    /// Bridge to the house `MetadataResult`, so these candidates can be ranked by
    /// `DiscIdentifier` alongside any other source. For an album release the
    /// title doubles as the album name.
    public var metadataResult: MetadataResult {
        MetadataResult(
            source: .musicBrainz,
            externalId: id,
            title: title,
            year: year,
            releaseDate: date,
            artist: artist,
            album: title
        )
    }
}

// MARK: - MusicBrainzDiscLookupService

/// Executes a keyless MusicBrainz disc/TOC lookup and maps the result to
/// `MusicBrainzDiscMatch` candidates. Modelled on `MusicBrainzLookupService`:
/// the same seam, throttle, cancellation handling and status→error mapping.
public struct MusicBrainzDiscLookupService: Sendable {
    private let httpClient: any MetadataHTTPClient
    private let throttle: MusicBrainzRequestThrottle

    public init(
        httpClient: any MetadataHTTPClient = URLSessionMetadataHTTPClient(),
        throttle: MusicBrainzRequestThrottle = .shared
    ) {
        self.httpClient = httpClient
        self.throttle = throttle
    }

    // MARK: TOC string (pure)

    /// Build the MusicBrainz TOC string for an Audio CD table of contents, or
    /// `nil` when it has no audio tracks. Only audio (Red Book) tracks count
    /// toward the MusicBrainz TOC; a trailing data track (Enhanced CD) is
    /// excluded. Every offset and the lead-out get the standard +150 pre-gap.
    public static func musicBrainzTOCString(for toc: DiscTableOfContents) -> String? {
        let audioTracks = toc.tracks
            .filter { !$0.isData }
            .sorted { $0.number < $1.number }
        guard let first = audioTracks.first, let last = audioTracks.last else { return nil }
        // Measured to the end of the MUSIC session, not the physical end of the
        // disc — that is what MusicBrainz matches on, and it is what differs on an
        // Enhanced CD. MUST stay in step with `MusicBrainzDiscID.compute(for:)`, or
        // the lookup and the disc's ID would describe different discs.
        guard let musicLeadOut = MusicBrainzDiscID.musicSessionLeadOutSector(for: toc) else { return nil }
        let offsets = audioTracks.map { $0.startSector + 150 }
        return AudioCDReader.buildMusicBrainzTOC(
            firstTrack: first.number,
            lastTrack: last.number,
            leadOutOffset: musicLeadOut.sector + 150,
            trackOffsets: offsets
        )
    }

    // MARK: Request (pure)

    /// Build the disc/TOC lookup request: the public `discid` fuzzy-TOC endpoint
    /// with `inc=artist-credits` so releases carry their artist. The `+`-joined
    /// TOC is passed through literally (it is numeric — no escaping needed),
    /// exactly as `AudioCDReader.buildMusicBrainzLookupURL` documents.
    public static func buildLookupRequest(tocString: String) -> URLRequest? {
        let urlString = "\(MetadataSource.musicBrainz.baseURL)/discid/-?toc=\(tocString)&inc=artist-credits&fmt=json"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = MusicBrainzClient.requestTimeoutSeconds
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: Lookup

    /// Look up an Audio CD by its table of contents. Throws `.emptyQuery` when the
    /// disc has no audio tracks.
    public func lookup(disc toc: DiscTableOfContents) async throws -> [MusicBrainzDiscMatch] {
        guard let tocString = Self.musicBrainzTOCString(for: toc) else {
            throw MusicBrainzLookupError.emptyQuery
        }
        return try await lookup(tocString: tocString)
    }

    /// Look up by an already-built MusicBrainz TOC string. Waits for the throttle,
    /// sends via the seam, maps status → error, parses 2xx. A 404 (no disc match)
    /// is a normal empty result, not an error. Cancellation rethrows
    /// `CancellationError`.
    public func lookup(tocString: String) async throws -> [MusicBrainzDiscMatch] {
        guard let request = Self.buildLookupRequest(tocString: tocString) else {
            throw MusicBrainzLookupError.invalidURL(
                "\(MetadataSource.musicBrainz.baseURL)/discid/-?toc=\(tocString)"
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
            return try Self.parseDiscLookup(data)
        case 404:
            return [] // No disc/TOC match — an ordinary "nothing found", not an error.
        case 503:
            throw MusicBrainzLookupError.rateLimited(serverMessage: Self.serverErrorMessage(from: data))
        case 400:
            throw MusicBrainzLookupError.badRequest(serverMessage: Self.serverErrorMessage(from: data))
        default:
            throw MusicBrainzLookupError.httpStatus(statusCode: response.statusCode, bodySnippet: Self.bodySnippet(data))
        }
    }

    // MARK: Parse (pure)

    /// Decode a `/ws/2/discid/-?toc=...&fmt=json` body into candidate releases,
    /// in server order. Releases with no usable title are dropped; every string
    /// is scrubbed with `MetadataSanitizer` (F-006: untrusted input).
    public static func parseDiscLookup(_ data: Data) throws -> [MusicBrainzDiscMatch] {
        let envelope: DiscLookupEnvelope
        do {
            envelope = try JSONDecoder().decode(DiscLookupEnvelope.self, from: data)
        } catch {
            throw MusicBrainzLookupError.malformedResponse(error.localizedDescription)
        }
        return (envelope.releases ?? []).compactMap { wire -> MusicBrainzDiscMatch? in
            let title = sanitize(wire.title ?? "")
            guard !title.isEmpty else { return nil }
            let joinedArtist = wire.artistCredit.map { credits in
                sanitize(credits.map { ($0.name ?? "") + ($0.joinphrase ?? "") }.joined())
            }
            let artist = (joinedArtist?.isEmpty ?? true) ? nil : joinedArtist
            let trackCount = wire.media.map { media in media.compactMap { $0.trackCount }.reduce(0, +) }
            return MusicBrainzDiscMatch(
                id: wire.id,
                title: title,
                artist: artist,
                date: wire.date.map(sanitize),
                country: wire.country.map(sanitize),
                trackCount: trackCount,
                mediumCount: wire.media?.count
            )
        }
    }

    // MARK: Private helpers (mirror MusicBrainzLookupService)

    private static func sanitize(_ raw: String) -> String {
        MetadataSanitizer.sanitizeSingleLine(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func serverErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            let error: String
            let help: String?
        }
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else { return nil }
        return sanitize(envelope.error)
    }

    private static func bodySnippet(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        return sanitize(String(text.prefix(200)))
    }
}

// MARK: - Wire format (private, kebab-case CodingKeys)

private struct DiscLookupEnvelope: Decodable {
    let releases: [WireDiscRelease]?
}

private struct WireDiscRelease: Decodable {
    let id: String
    let title: String?
    let date: String?
    let country: String?
    let artistCredit: [WireDiscArtistCredit]?
    let media: [WireDiscMedium]?

    enum CodingKeys: String, CodingKey {
        case id, title, date, country, media
        case artistCredit = "artist-credit"
    }
}

private struct WireDiscArtistCredit: Decodable {
    let name: String?
    let joinphrase: String?
}

private struct WireDiscMedium: Decodable {
    let trackCount: Int?

    enum CodingKeys: String, CodingKey {
        case trackCount = "track-count"
    }
}
