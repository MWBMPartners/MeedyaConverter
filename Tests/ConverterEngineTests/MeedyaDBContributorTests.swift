// ============================================================================
// MeedyaConverter — MeedyaDBContributorTests (Codex round-1 review, F1 + #507)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Two things landed together here, because they touch the same method:
//
//   * F1 — `MeedyaDBContributor.contribute` gained a `recheck` closure,
//     called immediately before the network call, so a run's promise about
//     contributing can be withdrawn or narrowed (never widened) if MeedyaDB's
//     settings change while the run is still going. This file proves the
//     four shapes that matter: no closure at all (today's unchanged
//     behaviour), a closure that withdraws, one that narrows the mode, and
//     one that tries to widen it and is refused.
//   * #507 — `contribute` also gained `declinedBecause`, so "the user never
//     asked" (`.off`) can be told apart from "the user asked but MeedyaDB
//     isn't finished being set up" (`.incomplete`) in the after-the-run
//     caption. Both used to collapse into the same generic wording.
//
// Against a mock `MetadataHTTPClient` throughout — no network in CI, exactly
// like `MeedyaDBPublisherTests`.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// Uniquely named so it never collides with the other HTTP stubs in this test
// module (`MeedyaDBPublisherTests`, `MusicDiscIdentificationTests`,
// `VideoDiscIdentificationTests` each keep their own, on purpose).
private final class ContributorStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Data] = []

    var callCount: Int { lock.withLock { bodies.count } }
    var lastBody: Data? { lock.withLock { bodies.last } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { bodies.append(request.httpBody ?? Data()) }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://db.example")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(#"{"discPublicId":"disc_1","matched":false}"#.utf8), response)
    }
}

/// Records whether a `@Sendable` closure ran. A class behind a lock because a
/// `@Sendable` closure may not mutate a captured local variable in Swift 6.
private final class ContributorRecheckCallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false

    func markCalled() { lock.withLock { called = true } }
    var wasCalled: Bool { lock.withLock { called } }
}

final class MeedyaDBContributorTests: XCTestCase {

    // MARK: - Fixtures

    /// Carries a MusicBrainz Disc ID, so `hasUsableIdentity` is true and the
    /// contributor gets as far as actually trying to send something —
    /// otherwise every case below would short-circuit on
    /// `noIdentityReason` before `recheck`/`declinedBecause` ever run.
    private func usableSubmission(labelText: String? = nil) -> MeedyaDBDiscSubmissionInputs {
        MeedyaDBDiscSubmissionInputs(
            disc: MeedyaDBDisc(discType: "audio_cd", musicBrainzDiscId: "abc123", labelText: labelText),
            identifiers: [MeedyaDBIdentifier(idType: "musicbrainz-discid", idValue: "abc123", source: "musicbrainz")]
        )
    }

    private func contributor(_ client: ContributorStubHTTPClient) -> MeedyaDBContributor {
        MeedyaDBContributor(
            publisher: MeedyaDBPublisher(
                config: MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "mdk_live_test", enabled: true),
                httpClient: client
            )
        )
    }

    private func sentPayload(_ client: ContributorStubHTTPClient) throws -> [String: Any] {
        let body = try XCTUnwrap(client.lastBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - F1: no `recheck` at all — today's behaviour must not change

    func test_noRecheck_sendsExactlyTheCapturedMode() async throws {
        let client = ContributorStubHTTPClient()
        let result = try await contributor(client).contribute(
            usableSubmission(),
            requested: true,
            mode: .full
        )

        XCTAssertEqual(client.callCount, 1)
        XCTAssertTrue(result.didSubmit)
        let sent = try sentPayload(client)
        XCTAssertEqual(sent["submission"] as? String, "full",
                       "with no recheck closure the captured mode must reach the wire unchanged")
    }

    // MARK: - F1: `recheck` returning nil withdraws the whole submission

    func test_recheck_returningNil_withdrawsAndSendsNothing() async throws {
        let client = ContributorStubHTTPClient()
        let result = try await contributor(client).contribute(
            usableSubmission(),
            requested: true,
            mode: .anonymous,
            recheck: { nil }
        )

        XCTAssertEqual(client.callCount, 0, "a withdrawn run must never touch the network")
        XCTAssertEqual(result, .notAttempted(reason: MeedyaDBContributor.withdrawnReason))
    }

    // MARK: - F1: `recheck` narrowing the mode is honoured

    func test_recheck_returningANarrowerMode_sendsTheNarrowerOne() async throws {
        let client = ContributorStubHTTPClient()
        let result = try await contributor(client).contribute(
            usableSubmission(labelText: "My Private Label"),
            requested: true,
            mode: .full,
            recheck: { .anonymous }
        )

        XCTAssertTrue(result.didSubmit)
        let sent = try sentPayload(client)
        XCTAssertEqual(sent["submission"] as? String, "anonymous",
                       "full narrowed to anonymous mid-run must actually narrow what is sent")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertNil(disc["labelText"], "narrowing to anonymous must still strip the label")
    }

    // MARK: - F1: `recheck` trying to WIDEN the mode is refused

    func test_recheck_returningAWiderMode_isRefused() async throws {
        // The whole point of narrowing rather than substituting: a `recheck`
        // closure that is wrong — buggy, or fed a stale value — must never be
        // able to make a run send MORE than it started out promising.
        let client = ContributorStubHTTPClient()
        let result = try await contributor(client).contribute(
            usableSubmission(labelText: "My Private Label"),
            requested: true,
            mode: .anonymous,
            recheck: { .full }
        )

        XCTAssertTrue(result.didSubmit)
        let sent = try sentPayload(client)
        XCTAssertEqual(sent["submission"] as? String, "anonymous",
                       "a recheck reporting `.full` must not widen a run that started `.anonymous`")
        let disc = try XCTUnwrap(sent["disc"] as? [String: Any])
        XCTAssertNil(disc["labelText"], "the label must stay off the wire despite the wider recheck")
    }

    // MARK: - F1: `recheck` reporting the SAME mode changes nothing

    func test_recheck_returningTheSameMode_stillSends() async throws {
        let client = ContributorStubHTTPClient()
        let result = try await contributor(client).contribute(
            usableSubmission(),
            requested: true,
            mode: .full,
            recheck: { .full }
        )

        XCTAssertEqual(client.callCount, 1, "nothing having changed must not itself block the send")
        XCTAssertTrue(result.didSubmit)
        let sent = try sentPayload(client)
        XCTAssertEqual(sent["submission"] as? String, "full")
    }

    // MARK: - #507: declinedBecause names the specific reason

    func test_declinedBecause_withAReason_usesItInsteadOfTheGenericWording() async throws {
        let client = ContributorStubHTTPClient()
        let specific = "Contributing is on, but MeedyaDB has no API key yet. Add one in Settings."

        let result = try await contributor(client).contribute(
            usableSubmission(),
            requested: false,
            mode: .anonymous,
            declinedBecause: specific
        )

        XCTAssertEqual(client.callCount, 0)
        XCTAssertEqual(result, .notAttempted(reason: specific))
        XCTAssertNotEqual(
            result.reason, MeedyaDBContributor.notRequestedReason,
            "the whole bug this fixes is these two collapsing into one wording"
        )
    }

    // MARK: - #507: absent declinedBecause falls back to the generic wording

    func test_declinedBecause_absent_fallsBackToNotRequestedReason() async throws {
        // This is BOTH of the callers that genuinely never asked: MeedyaDB
        // switched off outright, and the CLI run without `--submit` (which
        // never passes `declinedBecause` at all).
        let client = ContributorStubHTTPClient()

        let result = try await contributor(client).contribute(
            usableSubmission(),
            requested: false,
            mode: .anonymous
        )

        XCTAssertEqual(client.callCount, 0)
        XCTAssertEqual(result, .notAttempted(reason: MeedyaDBContributor.notRequestedReason))
    }

    // MARK: - `recheck` must never run when nothing was requested

    func test_recheck_isNeverCalledWhenNotRequested() async throws {
        let client = ContributorStubHTTPClient()
        // A lock-protected flag, not a plain `var`: `recheck` is `@Sendable`,
        // and Swift 6 refuses to let a `@Sendable` closure mutate a captured
        // local ("mutation of captured var … in concurrently-executing
        // code"). A plain `var` here broke the CI build on 9d47730 even
        // though `swiftc -parse` accepted it, because only a real type-check
        // sees the rule.
        let recheckFlag = ContributorRecheckCallFlag()

        _ = try await contributor(client).contribute(
            usableSubmission(),
            requested: false,
            mode: .anonymous,
            recheck: {
                recheckFlag.markCalled()
                return .full
            }
        )

        XCTAssertFalse(recheckFlag.wasCalled, "there is nothing to re-check for a run that was never asked to contribute")
    }

    // MARK: - #507: `MeedyaDBReadiness.declinedReason` pins the three cases apart

    func test_declinedReason_off_isNilSoNotRequestedReasonStillApplies() {
        let readiness = MeedyaDBReadiness.off(reason: MeedyaDBGate.offReason)
        XCTAssertNil(readiness.declinedReason, "never having asked must keep saying so, not name a missing piece")
    }

    func test_declinedReason_incomplete_carriesTheSpecificReason() {
        let readiness = MeedyaDBReadiness.incomplete(reason: MeedyaDBGate.missingKeyReason)
        XCTAssertEqual(readiness.declinedReason, MeedyaDBGate.missingKeyReason)
    }

    func test_declinedReason_ready_isNil() {
        let readiness = MeedyaDBReadiness.ready(
            MeedyaDBPublisherConfig(baseURL: "https://db.example", apiKey: "k", enabled: true)
        )
        XCTAssertNil(readiness.declinedReason, "a ready config has nothing to decline")
    }
}
