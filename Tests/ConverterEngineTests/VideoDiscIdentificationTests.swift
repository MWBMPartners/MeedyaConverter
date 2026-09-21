// ============================================================================
// MeedyaConverter — VideoDiscIdentificationTests (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Covers the video identify-and-contribute run against a MOCK HTTP seam — no
// disc, no MakeMKV, no MeedyaDB in CI.
//
// The emphasis is on what makes video DIFFERENT from music, because that is
// where a reader's music-path intuition will mislead them:
//
//   * there is no exact hit — identification is a ranked guess, and a disc
//     with NO candidates is a normal, useful outcome rather than a failure;
//   * a disc nobody can name is still contributed, on the strength of its
//     structural fingerprint alone, so MeedyaDB learns the disc exists;
//   * the shared failure posture (off is not failed, cancellation stays
//     cancellation) must behave identically to the music path, since both
//     now go through MeedyaDBContributor.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// Uniquely named so it never collides with the other stubs in this module.
private final class VideoIdentifyStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
    enum Outcome {
        case success(Data, Int)
        case failure(any Error)
    }

    private let lock = NSLock()
    private let outcome: Outcome
    private var requests: [URLRequest] = []

    init(_ outcome: Outcome) { self.outcome = outcome }

    var callCount: Int { lock.withLock { requests.count } }
    var lastBody: Data? { lock.withLock { requests.last?.httpBody } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        switch outcome {
        case .failure(let error):
            throw error
        case .success(let data, let code):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    }
}

final class VideoDiscIdentificationTests: XCTestCase {

    // MARK: - Fixtures

    /// A feature film disc: one long title plus a short extra.
    private func featureDisc() -> MakeMKVDiscInfo {
        MakeMKVBackend.parseInfo("""
        CINFO:32,0,"BIG_MOVIE_DISC"
        TINFO:0,9,0,"1:57:21"
        TINFO:0,8,0,"12"
        TINFO:1,9,0,"0:04:12"
        """)
    }

    /// A disc MakeMKV could read nothing useful from.
    private func emptyDisc() -> MakeMKVDiscInfo {
        MakeMKVBackend.parseInfo(#"CINFO:32,0,"UNKNOWN_DISC""#)
    }

    private func candidate(
        title: String,
        runtimeMinutes: Int?,
        year: Int? = 2011,
        id: String = "tmdb-1"
    ) -> MetadataResult {
        MetadataResult(
            source: .tmdb,
            externalId: id,
            title: title,
            year: year,
            runtimeMinutes: runtimeMinutes
        )
    }

    private let ingestJSON = Data("""
    {"discPublicId":"disc_video_1","matched":false}
    """.utf8)

    private func publisher(
        _ client: VideoIdentifyStubHTTPClient,
        enabled: Bool = true
    ) -> MeedyaDBPublisher {
        MeedyaDBPublisher(
            config: MeedyaDBPublisherConfig(
                baseURL: "https://db.example",
                apiKey: "mdk_live_test",
                enabled: enabled
            ),
            httpClient: client
        )
    }

    private func sentPayload(_ client: VideoIdentifyStubHTTPClient) throws -> [String: Any] {
        let body = try XCTUnwrap(client.lastBody, "expected a request body")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - Signals are computed offline

    func test_signals_comeFromTheDiscsOwnContent() {
        let signals = VideoDiscIdentifier.signals(for: featureDisc(), discType: .dvdVideo)

        XCTAssertEqual(signals.discType, .dvdVideo)
        XCTAssertEqual(signals.mainFeatureDurationSeconds, 7041, "1:57:21 is the longest title")
        XCTAssertEqual(signals.titleDurationsSeconds.count, 2)
        XCTAssertEqual(signals.label, "BIG_MOVIE_DISC")
    }

    // MARK: - A disc nobody can name is still worth contributing

    func test_identify_noCandidates_stillContributesTheDiscsStructure() async throws {
        let client = VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = VideoDiscIdentifier(publisher: publisher(client))

        let result = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)

        XCTAssertFalse(result.hasCandidates)
        XCTAssertNil(result.bestMatch)
        XCTAssertEqual(client.callCount, 1,
                       "a disc nobody can name is exactly the one MeedyaDB has not heard of")
        XCTAssertTrue(result.contribution.didSubmit)

        let submission = try XCTUnwrap(result.submission)
        XCTAssertNotNil(submission.disc.tocFingerprint,
                        "the structural fingerprint is what makes an unnamed disc matchable later")
        XCTAssertTrue(submission.hasUsableIdentity)
    }

    func test_identify_noCandidates_isNotReportedAsAFailure() async throws {
        let identifier = VideoDiscIdentifier(
            publisher: publisher(VideoIdentifyStubHTTPClient(.success(ingestJSON, 200)))
        )

        let result = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)

        if case .failed = result.contribution {
            XCTFail("having nothing to compare against is not a failure")
        }
        XCTAssertEqual(result.summary, "Nothing to compare this disc against yet, so it hasn't been named.")
    }

    // MARK: - Ranking is a guess, and says so

    func test_identify_ranksCandidatesByHowWellTheyFitTheDisc() async throws {
        let identifier = VideoDiscIdentifier(
            publisher: publisher(VideoIdentifyStubHTTPClient(.success(ingestJSON, 200)))
        )

        // 7041s is 117.35 minutes. The 117-minute candidate fits; the
        // 45-minute one does not.
        let result = try await identifier.identify(
            info: featureDisc(),
            discType: .dvdVideo,
            candidates: [
                candidate(title: "Something Much Shorter", runtimeMinutes: 45, id: "tmdb-short"),
                candidate(title: "The Right Film", runtimeMinutes: 117, id: "tmdb-right"),
            ]
        )

        XCTAssertEqual(result.ranked.count, 2)
        XCTAssertEqual(result.bestMatch?.candidate.title, "The Right Film",
                       "the candidate whose running time matches the disc must win")
        XCTAssertGreaterThan(
            try XCTUnwrap(result.ranked.first).score.confidence,
            try XCTUnwrap(result.ranked.last).score.confidence
        )
    }

    func test_summary_presentsTheResultAsAGuessNotAFact() async throws {
        let identifier = VideoDiscIdentifier()

        let result = try await identifier.identify(
            info: featureDisc(),
            discType: .dvdVideo,
            candidates: [candidate(title: "The Right Film", runtimeMinutes: 117)],
            contribute: false
        )

        XCTAssertTrue(result.summary.hasPrefix("Best guess: The Right Film ("),
                      "a ranked guess presented as fact is how a disc gets filed under the wrong film")
        XCTAssertTrue(result.summary.contains("% confident"))
    }

    func test_summary_saysSoWhenTheDiscHasNoReadableTitles() async throws {
        let identifier = VideoDiscIdentifier()

        let result = try await identifier.identify(
            info: emptyDisc(),
            discType: .dvdVideo,
            contribute: false
        )

        XCTAssertEqual(result.summary, "This disc has no readable titles, so there is nothing to identify.")
    }

    // MARK: - The shared failure posture behaves as it does for music

    func test_identify_meedyaDBDisabled_isNotAttemptedNotFailed() async throws {
        let client = VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = VideoDiscIdentifier(publisher: publisher(client, enabled: false))

        let result = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)

        XCTAssertEqual(client.callCount, 0, "a disabled publisher must not touch the network")
        XCTAssertFalse(result.contribution.didSubmit)
        if case .failed = result.contribution {
            XCTFail("publishing being switched off must never be reported as a failure")
        }
    }

    func test_identify_contributeFalse_neverTouchesThePublisher() async throws {
        let client = VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = VideoDiscIdentifier(publisher: publisher(client))

        let result = try await identifier.identify(
            info: featureDisc(),
            discType: .dvdVideo,
            contribute: false
        )

        XCTAssertEqual(client.callCount, 0)
        XCTAssertEqual(
            result.contribution,
            .notAttempted(reason: MeedyaDBContributor.notRequestedReason)
        )
        XCTAssertNotNil(result.submission, "what WOULD have been sent is still worth showing")
    }

    func test_identify_meedyaDBRejectsTheKey_isReportedAsFailedNotThrown() async throws {
        let identifier = VideoDiscIdentifier(
            publisher: publisher(VideoIdentifyStubHTTPClient(.success(Data(), 401)))
        )

        let result = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)

        guard case .failed = result.contribution else {
            return XCTFail("a rejected API key is a real failure, not a quiet skip")
        }
    }

    func test_identify_cancellationPropagatesAndIsNotAFailure() async {
        let identifier = VideoDiscIdentifier(
            publisher: publisher(VideoIdentifyStubHTTPClient(.failure(CancellationError())))
        )

        do {
            _ = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)
            XCTFail("cancellation must propagate, not be folded into a result")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - The candidate-provider seam

    func test_providerSuppliesCandidatesWhenTheCallerHasNone() async throws {
        let identifier = VideoDiscIdentifier(
            publisher: publisher(VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))),
            // Built inline rather than via a helper: the closure is
            // `@Sendable` and XCTestCase is not Sendable, so capturing
            // `self` here would not compile.
            candidateProvider: { _ in
                [MetadataResult(
                    source: .tmdb,
                    externalId: "tmdb-provider",
                    title: "From The Provider",
                    year: 2011,
                    runtimeMinutes: 117
                )]
            }
        )

        let result = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)

        XCTAssertEqual(result.bestMatch?.candidate.title, "From The Provider")
        XCTAssertNil(result.lookupFailure)
    }

    func test_callerSuppliedCandidatesWinOverTheProvider() async throws {
        // The caller knows more than a volume-label search ever will, so the
        // provider must not override or supplement them.
        let identifier = VideoDiscIdentifier(
            publisher: publisher(VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))),
            candidateProvider: { _ in
                XCTFail("the provider must not run when the caller supplied candidates")
                return []
            }
        )

        let result = try await identifier.identify(
            info: featureDisc(),
            discType: .dvdVideo,
            candidates: [candidate(title: "From The Caller", runtimeMinutes: 117)]
        )

        XCTAssertEqual(result.ranked.count, 1)
        XCTAssertEqual(result.bestMatch?.candidate.title, "From The Caller")
    }

    func test_providerFailureDoesNotAbandonTheRun() async throws {
        // Same posture as the music path: the disc's structure is still worth
        // contributing when the lookup fails, and the outage is REPORTED
        // rather than hidden.
        let client = VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = VideoDiscIdentifier(
            publisher: publisher(client),
            candidateProvider: { _ in throw URLError(.notConnectedToInternet) }
        )

        let result = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)

        XCTAssertNotNil(result.lookupFailure, "the outage must be reported, not swallowed")
        XCTAssertFalse(result.hasCandidates)
        XCTAssertEqual(client.callCount, 1, "the disc is still contributed on its structure")
        XCTAssertTrue(result.contribution.didSubmit)
        XCTAssertTrue(result.summary.hasPrefix("Couldn't check with the film database:"))
    }

    func test_providerCancellationPropagates() async {
        let identifier = VideoDiscIdentifier(
            publisher: publisher(VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))),
            candidateProvider: { _ in throw CancellationError() }
        )

        do {
            _ = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)
            XCTFail("cancellation must stop the run, not be treated as an outage")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func test_noProviderMeansNoLookupFailure() async throws {
        // Nothing was configured, so nothing failed — `lookupFailure` must
        // stay nil rather than reporting an absence as an error.
        let identifier = VideoDiscIdentifier(
            publisher: publisher(VideoIdentifyStubHTTPClient(.success(ingestJSON, 200)))
        )

        let result = try await identifier.identify(info: featureDisc(), discType: .dvdVideo)

        XCTAssertNil(result.lookupFailure)
        XCTAssertEqual(result.summary, "Nothing to compare this disc against yet, so it hasn't been named.")
    }

    // MARK: - Privacy: the label must not leak in anonymous mode

    func test_identify_anonymousMode_neverPutsTheLabelOnTheWire() async throws {
        let client = VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = VideoDiscIdentifier(publisher: publisher(client))

        let result = try await identifier.identify(
            info: featureDisc(),
            discType: .dvdVideo,
            labelText: "My Private Disc Label",
            mode: .anonymous
        )

        XCTAssertTrue(result.contribution.didSubmit)
        let sent = try sentPayload(client)
        XCTAssertEqual(sent["submission"] as? String, "anonymous")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertNil(disc["labelText"], "the label must never leave the machine in anonymous mode")
    }

    func test_identify_fullMode_doesSendTheLabel() async throws {
        let client = VideoIdentifyStubHTTPClient(.success(ingestJSON, 200))
        let identifier = VideoDiscIdentifier(publisher: publisher(client))

        _ = try await identifier.identify(
            info: featureDisc(),
            discType: .dvdVideo,
            labelText: "My Private Disc Label",
            mode: .full
        )

        let sent = try sentPayload(client)
        XCTAssertEqual(sent["submission"] as? String, "full")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertEqual(disc["labelText"] as? String, "My Private Disc Label")
    }
}
