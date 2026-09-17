// ============================================================================
// MeedyaConverter — MeedyaDBPublisher (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Contribute an identified disc's identifiers to MeedyaDB — the family's combined
// media-information database — via its `disc_ingest` endpoint, and get back a
// MeedyaDB id to store against the disc.
//
// PRIVACY (owner decision): submission is **anonymised by default** — only the
// disc's structural facts (type, TOC fingerprint, MusicBrainz disc id, track
// count) and public identifiers/candidate matches are sent; the disc's printed
// label text (the one field that could carry user-specific text) is included
// ONLY in `.full` mode, which the user opts into. Publishing is **off unless the
// user configures and enables it** (base URL + API key).
//
// It reuses the injectable `MetadataHTTPClient` seam (so it is unit-tested with
// canned responses and never hits the network in CI), exactly like the MusicBrainz
// services. Targets the contract in the MeedyaDB repo's
// docs/api-schema-design.md (v1 bare response: {discPublicId, matched,
// releasePublicId}).
// ============================================================================

import Foundation

// MARK: - Submission model

/// How much to submit. `.anonymous` (default) sends identifiers + structural facts
/// only; `.full` additionally sends the disc's label text (opt-in).
public enum MeedyaDBSubmissionMode: String, Sendable {
    case anonymous
    case full
}

/// The disc block of a `disc_ingest` submission.
public struct MeedyaDBDisc: Encodable, Sendable, Equatable {
    public var discType: String
    public var tocFingerprint: String?
    public var musicBrainzDiscId: String?
    public var trackCount: Int?
    /// Only populated in `.full` mode.
    public var labelText: String?

    public init(
        discType: String,
        tocFingerprint: String? = nil,
        musicBrainzDiscId: String? = nil,
        trackCount: Int? = nil,
        labelText: String? = nil
    ) {
        self.discType = discType
        self.tocFingerprint = tocFingerprint
        self.musicBrainzDiscId = musicBrainzDiscId
        self.trackCount = trackCount
        self.labelText = labelText
    }
}

/// One external identifier in a submission.
public struct MeedyaDBIdentifier: Encodable, Sendable, Equatable {
    public var idType: String
    public var idValue: String
    public var source: String?

    public init(idType: String, idValue: String, source: String? = nil) {
        self.idType = idType
        self.idValue = idValue
        self.source = source
    }
}

/// One candidate identity in a submission.
public struct MeedyaDBCandidate: Encodable, Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var year: Int?
    public var identifiers: [MeedyaDBIdentifier]
    public var confidence: Double?

    public init(
        title: String,
        artist: String? = nil,
        year: Int? = nil,
        identifiers: [MeedyaDBIdentifier] = [],
        confidence: Double? = nil
    ) {
        self.title = title
        self.artist = artist
        self.year = year
        self.identifiers = identifiers
        self.confidence = confidence
    }
}

/// The full `disc_ingest` request body.
public struct MeedyaDBSubmission: Encodable, Sendable, Equatable {
    public var submission: String
    public var disc: MeedyaDBDisc
    public var identifiers: [MeedyaDBIdentifier]
    public var candidates: [MeedyaDBCandidate]

    public init(
        submission: String,
        disc: MeedyaDBDisc,
        identifiers: [MeedyaDBIdentifier],
        candidates: [MeedyaDBCandidate]
    ) {
        self.submission = submission
        self.disc = disc
        self.identifiers = identifiers
        self.candidates = candidates
    }
}

/// The `disc_ingest` result (v1 bare shape).
public struct MeedyaDBIngestResult: Decodable, Sendable, Equatable {
    public var discPublicId: String
    public var matched: Bool
    public var releasePublicId: String?

    public init(discPublicId: String, matched: Bool, releasePublicId: String? = nil) {
        self.discPublicId = discPublicId
        self.matched = matched
        self.releasePublicId = releasePublicId
    }
}

// MARK: - Config + errors

/// Where and whether to publish. All three must be set/true for publishing to run.
public struct MeedyaDBPublisherConfig: Sendable, Equatable {
    /// MeedyaDB base URL, e.g. "https://meedyadb.example". No trailing slash needed.
    public var baseURL: String
    /// A MeedyaDB API key (mdk_live_…) with the `disc:ingest` scope.
    public var apiKey: String
    /// Master switch — publishing never happens unless this is true.
    public var enabled: Bool

    public init(baseURL: String = "", apiKey: String = "", enabled: Bool = false) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.enabled = enabled
    }

    /// Whether the config is complete enough to publish.
    public var isUsable: Bool {
        enabled
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum MeedyaDBPublishError: Error, Sendable, Equatable, LocalizedError {
    /// Publishing is switched off.
    case disabled
    /// Publishing is on but the base URL / API key is missing.
    case notConfigured
    case invalidURL(String)
    case unauthorized
    case rateLimited
    case httpStatus(statusCode: Int, bodySnippet: String)
    case transport(String)
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "MeedyaDB publishing is turned off."
        case .notConfigured:
            return "MeedyaDB publishing is on, but the server address or API key is missing."
        case .invalidURL(let url):
            return "The MeedyaDB request URL could not be formed: \(url)"
        case .unauthorized:
            return "MeedyaDB rejected the API key (HTTP 401)."
        case .rateLimited:
            return "MeedyaDB is rate-limiting requests (HTTP 429). Try again shortly."
        case .httpStatus(let statusCode, let bodySnippet):
            return "MeedyaDB returned HTTP \(statusCode): \(bodySnippet)"
        case .transport(let message):
            return "Could not reach MeedyaDB: \(message)"
        case .malformedResponse(let message):
            return "MeedyaDB returned a response that could not be read: \(message)"
        }
    }
}

// MARK: - MeedyaDBPublisher

/// Submits an identified disc to MeedyaDB's `disc_ingest` endpoint.
public struct MeedyaDBPublisher: Sendable {
    private let config: MeedyaDBPublisherConfig
    private let httpClient: any MetadataHTTPClient

    public init(
        config: MeedyaDBPublisherConfig,
        httpClient: any MetadataHTTPClient = URLSessionMetadataHTTPClient()
    ) {
        self.config = config
        self.httpClient = httpClient
    }

    // MARK: Payload (pure)

    /// Build the submission body for the given mode. In `.anonymous` mode the
    /// disc's label text is dropped; everything else (identifiers, candidates,
    /// structural facts) is kept.
    public static func buildSubmission(
        disc: MeedyaDBDisc,
        identifiers: [MeedyaDBIdentifier],
        candidates: [MeedyaDBCandidate],
        mode: MeedyaDBSubmissionMode
    ) -> MeedyaDBSubmission {
        var scrubbedDisc = disc
        if mode == .anonymous {
            scrubbedDisc.labelText = nil
        }
        return MeedyaDBSubmission(
            submission: mode.rawValue,
            disc: scrubbedDisc,
            identifiers: identifiers,
            candidates: candidates
        )
    }

    // MARK: Request (pure)

    /// Build the `disc_ingest` POST request from a submission body.
    public func buildRequest(for submission: MeedyaDBSubmission) throws -> URLRequest {
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let urlString = "\(trimmedBase)/api?action=disc_ingest"
        guard let url = URL(string: urlString) else {
            throw MeedyaDBPublishError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(config.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(submission)
        return request
    }

    // MARK: Submit

    /// Publish an identified disc to MeedyaDB. Throws `.disabled`/`.notConfigured`
    /// when publishing is off or incompletely configured (so callers can no-op
    /// silently). Cancellation rethrows `CancellationError`.
    public func submit(
        disc: MeedyaDBDisc,
        identifiers: [MeedyaDBIdentifier] = [],
        candidates: [MeedyaDBCandidate] = [],
        mode: MeedyaDBSubmissionMode = .anonymous
    ) async throws -> MeedyaDBIngestResult {
        guard config.enabled else { throw MeedyaDBPublishError.disabled }
        guard config.isUsable else { throw MeedyaDBPublishError.notConfigured }

        let submission = Self.buildSubmission(
            disc: disc,
            identifiers: identifiers,
            candidates: candidates,
            mode: mode
        )
        let request = try buildRequest(for: submission)

        let result: (Data, HTTPURLResponse)
        do {
            result = try await httpClient.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MeedyaDBPublishError.transport(error.localizedDescription)
        }

        let (data, response) = result
        switch response.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(MeedyaDBIngestResult.self, from: data)
            } catch {
                throw MeedyaDBPublishError.malformedResponse(error.localizedDescription)
            }
        case 401, 403:
            throw MeedyaDBPublishError.unauthorized
        case 429:
            throw MeedyaDBPublishError.rateLimited
        default:
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
            throw MeedyaDBPublishError.httpStatus(statusCode: response.statusCode, bodySnippet: snippet)
        }
    }
}
