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
// everything below it.
//
// EXACT vs FUZZY (Codex round-1 review, finding F6) — this is the part that used
// to be wrong, so it is worth spelling out plainly.
//
// The request always names the disc's OWN computed Disc ID:
// `/discid/<discID>?toc=<toc>&cdstubs=no&inc=...&fmt=json`. This used to be sent
// as `/discid/-?toc=...`, which MusicBrainz's docs say explicitly makes it IGNORE
// the Disc ID and run a fuzzy TOC-only search — so the disc's own, near-unique
// identity was computed and then never actually used. `cdstubs=no` matters too: a
// "CD stub" (a bare, unofficial listing with no proper release) would otherwise
// satisfy the exact lookup and short-circuit the fuzzy fallback this file relies
// on, and this file has no model for a stub's shape at all.
//
// MusicBrainz replies with one of two different SHAPES for the same endpoint, and
// telling them apart is the whole fix:
//   * EXACT — the disc it holds under that id: a top-level object with
//     `id, offset-count, offsets, sectors, releases`. Every release in `releases`
//     really is this disc (or another pressing sharing the same TOC).
//   * FUZZY — MusicBrainz didn't recognise the id (or none was given, or a CD
//     stub was skipped past), so it fell back to matching the TOC's track
//     lengths against ITS WHOLE DATABASE: a top-level object with
//     `release-count, release-offset, releases` and no top-level `id`/`offsets`
//     at all. These releases are competing GUESSES, most of which do not
//     actually carry this disc's Disc ID — confirmed live against MusicBrainz's
//     own Nevermind example on 2026-09-24: the fuzzy search for that disc came
//     back with 25 releases, of which only 5 actually match.
// `parseDiscLookup` tells them apart the FAIL-SAFE way: `.exact` only when the
// top-level `id` equals the id THIS APP asked for and `offsets` is present.
// Anything else — the fuzzy shape, a shape this app doesn't recognise, or (this
// really can happen: MusicBrainz falls back to fuzzy on an unknown id without
// changing the URL) an "exact-looking" body whose `id` doesn't match what was
// asked for — is `.fuzzy`. Getting this the other way around is exactly the bug
// being fixed: a guess reported, and previously submitted to MeedyaDB, as fact.
// ============================================================================

import Foundation

// MARK: - MusicBrainzDiscMatch

/// One candidate album release returned by a MusicBrainz disc/TOC lookup.
/// Whether this is a confirmed hit or only a best guess is NOT carried on the
/// match itself — see `MusicBrainzDiscLookupResult.matchKind`, which applies
/// to the whole list of matches at once.
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

// MARK: - MusicBrainzDiscMatchKind

/// How sure a MusicBrainz disc/TOC lookup was — see this file's header for the
/// two response shapes this distinguishes.
///
/// FAIL SAFE BY CONSTRUCTION: `MusicBrainzDiscLookupService.parseDiscLookup`
/// only ever returns `.exact` for the one shape MusicBrainz's docs define as
/// unambiguous. Every other shape — including ones this app has never seen —
/// comes back `.fuzzy`. A wrong `.fuzzy` costs some wording; a wrong `.exact`
/// turns a guess into a fact MeedyaDB stores forever (see `MeedyaDBSubmissionBuilder`).
public enum MusicBrainzDiscMatchKind: Sendable, Equatable {
    /// MusicBrainz's own disc listing named this exact TOC/Disc ID.
    case exact
    /// Everything else: MusicBrainz did not recognise this disc and is
    /// offering its closest guess from similar track lengths, or the response
    /// had a shape this app does not recognise as the exact one.
    case fuzzy
}

// MARK: - MusicBrainzDiscLookupResult

/// One completed disc/TOC lookup: the releases MusicBrainz returned, and
/// whether that was because it recognised this exact disc or is only guessing.
public struct MusicBrainzDiscLookupResult: Sendable, Equatable {
    public let matchKind: MusicBrainzDiscMatchKind
    /// In server order. Empty means MusicBrainz has no answer at all — not
    /// even a guess — regardless of `matchKind`.
    public let matches: [MusicBrainzDiscMatch]

    public init(matchKind: MusicBrainzDiscMatchKind, matches: [MusicBrainzDiscMatch]) {
        self.matchKind = matchKind
        self.matches = matches
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

    /// Build the disc/TOC lookup request against the disc's OWN computed Disc
    /// ID — never `-` (see this file's header on why `-` was wrong: it tells
    /// MusicBrainz to ignore the id and go straight to a fuzzy search).
    /// `cdstubs=no` so a bare CD-stub listing can't short-circuit MusicBrainz's
    /// own fallback to a fuzzy search (this app has no model for a stub's
    /// shape). `inc=artist-credits` so releases carry their artist. The
    /// `+`-joined TOC is passed through literally (it is numeric — no escaping
    /// needed), exactly as `AudioCDReader.buildMusicBrainzLookupURL` documents.
    /// `nil` when `discID` is empty — a request with nothing to ask about.
    public static func buildLookupRequest(discID: String, tocString: String) -> URLRequest? {
        guard !discID.isEmpty else { return nil }
        let urlString = "\(MetadataSource.musicBrainz.baseURL)/discid/\(discID)?toc=\(tocString)&cdstubs=no&inc=artist-credits&fmt=json"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = MusicBrainzClient.requestTimeoutSeconds
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: Lookup

    /// Look up an Audio CD by its table of contents and its own computed
    /// (music-only) Disc ID. Throws `.emptyQuery` when the disc has no audio
    /// tracks, in which case there is nothing to build a TOC string from
    /// either — `discID` is supplied by the caller so this file never has to
    /// re-decide the "stored vs. computed" preference `MusicDiscIdentifier`
    /// and `MeedyaDBSubmissionBuilder` already make (they MUST all agree, or
    /// the app would look one disc up while showing/submitting another).
    public func lookup(disc toc: DiscTableOfContents, discID: String) async throws -> MusicBrainzDiscLookupResult {
        guard let tocString = Self.musicBrainzTOCString(for: toc) else {
            throw MusicBrainzLookupError.emptyQuery
        }
        return try await lookup(discID: discID, tocString: tocString)
    }

    /// Look up by an already-built Disc ID and MusicBrainz TOC string. Waits
    /// for the throttle, sends via the seam, maps status → error, parses 2xx.
    /// A 404 (no disc match at all, exact or fuzzy) is a normal empty result,
    /// not an error. Cancellation rethrows `CancellationError`.
    public func lookup(discID: String, tocString: String) async throws -> MusicBrainzDiscLookupResult {
        guard let request = Self.buildLookupRequest(discID: discID, tocString: tocString) else {
            throw MusicBrainzLookupError.invalidURL(
                "\(MetadataSource.musicBrainz.baseURL)/discid/\(discID)?toc=\(tocString)"
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
            return try Self.parseDiscLookup(data, requestedDiscID: discID)
        case 404:
            // No disc/TOC match at all — an ordinary "nothing found", not an
            // error. `matchKind` is moot with an empty list (nothing for it to
            // describe), so `.fuzzy` here is just the fail-safe default.
            return MusicBrainzDiscLookupResult(matchKind: .fuzzy, matches: [])
        case 503:
            throw MusicBrainzLookupError.rateLimited(serverMessage: Self.serverErrorMessage(from: data))
        case 400:
            throw MusicBrainzLookupError.badRequest(serverMessage: Self.serverErrorMessage(from: data))
        default:
            throw MusicBrainzLookupError.httpStatus(statusCode: response.statusCode, bodySnippet: Self.bodySnippet(data))
        }
    }

    // MARK: Parse (pure)

    /// Decode a `/ws/2/discid/<id>?toc=...&fmt=json` body into candidate
    /// releases plus the match kind, in server order. Releases with no usable
    /// title are dropped; every string is scrubbed with `MetadataSanitizer`
    /// (F-006: untrusted input).
    ///
    /// `requestedDiscID` is the id THIS APP asked for — needed because the
    /// only sound way to call a response "exact" is to check it actually
    /// answers the question asked, not merely that it "looks like" the exact
    /// shape. See this file's header for the two shapes and why every other
    /// case is `.fuzzy` (fail safe: Codex round-1 review, finding F6).
    public static func parseDiscLookup(_ data: Data, requestedDiscID: String) throws -> MusicBrainzDiscLookupResult {
        let envelope: DiscLookupEnvelope
        do {
            envelope = try JSONDecoder().decode(DiscLookupEnvelope.self, from: data)
        } catch {
            throw MusicBrainzLookupError.malformedResponse(error.localizedDescription)
        }
        let matches = (envelope.releases ?? []).compactMap { wire -> MusicBrainzDiscMatch? in
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
        // `.exact` ONLY when BOTH hold: the top-level `id` names exactly the
        // disc this app asked about, AND `offsets` — which only the exact
        // shape carries — is present. Everything else (the fuzzy shape; an
        // unrecognised shape; an "exact-looking" body that happens to name a
        // DIFFERENT id, which is possible because MusicBrainz can fall back to
        // fuzzy without changing the URL) is `.fuzzy`.
        let isExact = envelope.id == requestedDiscID && envelope.offsets != nil
        return MusicBrainzDiscLookupResult(matchKind: isExact ? .exact : .fuzzy, matches: matches)
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
    /// Present ONLY on the exact shape: MusicBrainz's own id for the disc it
    /// matched. Absent on the fuzzy/search shape (`release-count`,
    /// `release-offset`, `releases`) — that absence is half of what
    /// `parseDiscLookup` uses to tell the two apart.
    let id: String?
    /// Present ONLY on the exact shape: the disc's own per-track sector
    /// offsets. Only its PRESENCE is checked, never its content — see
    /// `parseDiscLookup`.
    let offsets: [Int]?
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
