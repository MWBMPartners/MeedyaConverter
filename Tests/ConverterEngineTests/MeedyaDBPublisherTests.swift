// ============================================================================
// MeedyaConverter — MeedyaDBPublisherTests (Issue #502)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Coverage for the MeedyaDB publishing hook: anonymised-vs-full payload building,
// request building, and the submit() status/error mapping — all against a mock
// MetadataHTTPClient (no network in CI). Public API only; no @testable import.
// ============================================================================

import Foundation
import XCTest
import ConverterEngine

// Uniquely named so it never collides with other stubs in this test module.
private final class MeedyaDBStubHTTPClient: MetadataHTTPClient, @unchecked Sendable {
    enum Outcome {
        case success(Data, Int)
        case failure(Error)
    }
    private let outcome: Outcome
    init(_ outcome: Outcome) { self.outcome = outcome }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch outcome {
        case .failure(let error):
            throw error
        case .success(let data, let code):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://meedyadb.example")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    }
}

final class MeedyaDBPublisherTests: XCTestCase {

    private func publisher(
        _ outcome: MeedyaDBStubHTTPClient.Outcome,
        enabled: Bool = true,
        apiKey: String = "mdk_live_test",
        baseURL: String = "https://db.example"
    ) -> MeedyaDBPublisher {
        MeedyaDBPublisher(
            config: MeedyaDBPublisherConfig(baseURL: baseURL, apiKey: apiKey, enabled: enabled),
            httpClient: MeedyaDBStubHTTPClient(outcome)
        )
    }

    private func discWithLabel() -> MeedyaDBDisc {
        MeedyaDBDisc(
            discType: "audio_cd",
            tocFingerprint: "1+2+250150+150+20150",
            musicBrainzDiscId: nil,
            trackCount: 17,
            labelText: "My Home-Labelled Disc"
        )
    }

    private func encodedDict(_ submission: MeedyaDBSubmission) throws -> [String: Any] {
        let data = try JSONEncoder().encode(submission)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Payload building

    func test_buildSubmission_anonymousDropsLabelText() throws {
        let sub = MeedyaDBPublisher.buildSubmission(
            disc: discWithLabel(),
            identifiers: [MeedyaDBIdentifier(idType: "musicbrainz-release", idValue: "mbid-1", source: "musicbrainz")],
            candidates: [],
            mode: .anonymous
        )
        XCTAssertEqual(sub.submission, "anonymous")
        XCTAssertNil(sub.disc.labelText)
        let dict = try encodedDict(sub)
        let disc = try XCTUnwrap(dict["disc"] as? [String: Any])
        XCTAssertNil(disc["labelText"], "labelText must be omitted in anonymous mode")
        XCTAssertEqual(disc["trackCount"] as? Int, 17)
    }

    func test_buildSubmission_fullKeepsLabelText() throws {
        let sub = MeedyaDBPublisher.buildSubmission(
            disc: discWithLabel(),
            identifiers: [],
            candidates: [],
            mode: .full
        )
        XCTAssertEqual(sub.submission, "full")
        XCTAssertEqual(sub.disc.labelText, "My Home-Labelled Disc")
        let dict = try encodedDict(sub)
        let disc = try XCTUnwrap(dict["disc"] as? [String: Any])
        XCTAssertEqual(disc["labelText"] as? String, "My Home-Labelled Disc")
    }

    // MARK: - Request building

    func test_buildRequest_urlHeadersAndBody() throws {
        let pub = publisher(.success(Data(), 200), baseURL: "https://db.example/") // trailing slash
        let sub = MeedyaDBPublisher.buildSubmission(disc: discWithLabel(), identifiers: [], candidates: [], mode: .anonymous)
        let request = try pub.buildRequest(for: sub)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://db.example/api?action=disc_ingest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "mdk_live_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(dict["submission"] as? String, "anonymous")
    }

    // MARK: - Config guards

    func test_submit_disabledThrows() async {
        let pub = publisher(.success(Data(), 200), enabled: false)
        await assertThrows(pub, expected: .disabled)
    }

    func test_submit_notConfiguredThrows() async {
        let pub = publisher(.success(Data(), 200), enabled: true, apiKey: "")
        await assertThrows(pub, expected: .notConfigured)
    }

    // MARK: - Submit status mapping

    func test_submit_success() async throws {
        let json = Data(#"{"discPublicId":"abc123","matched":true,"releasePublicId":"rel-9"}"#.utf8)
        let pub = publisher(.success(json, 200))
        let result = try await pub.submit(disc: discWithLabel())
        XCTAssertEqual(result.discPublicId, "abc123")
        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.releasePublicId, "rel-9")
    }

    func test_submit_successNullRelease() async throws {
        let json = Data(#"{"discPublicId":"abc123","matched":false,"releasePublicId":null}"#.utf8)
        let pub = publisher(.success(json, 200))
        let result = try await pub.submit(disc: discWithLabel())
        XCTAssertFalse(result.matched)
        XCTAssertNil(result.releasePublicId)
    }

    func test_submit_unauthorized() async {
        await assertThrows(publisher(.success(Data("{}".utf8), 401)), expected: .unauthorized)
    }

    func test_submit_rateLimited() async {
        await assertThrows(publisher(.success(Data("{}".utf8), 429)), expected: .rateLimited)
    }

    func test_submit_malformed() async {
        let pub = publisher(.success(Data("not json".utf8), 200))
        do {
            _ = try await pub.submit(disc: discWithLabel())
            XCTFail("expected an error")
        } catch let error as MeedyaDBPublishError {
            guard case .malformedResponse = error else { return XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_submit_cancellationRethrows() async {
        let pub = publisher(.failure(CancellationError()))
        do {
            _ = try await pub.submit(disc: discWithLabel())
            XCTFail("expected an error")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - Helper

    private func assertThrows(
        _ pub: MeedyaDBPublisher,
        expected: MeedyaDBPublishError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await pub.submit(disc: discWithLabel())
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as MeedyaDBPublishError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("wrong error type: \(error)", file: file, line: line)
        }
    }
}
