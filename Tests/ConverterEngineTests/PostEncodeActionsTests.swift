// ============================================================================
// MeedyaConverter — PostEncodeActionsTests (Issue #450 test coverage — roadmap #9)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// `PostEncodeActions.swift` (the post-encode action chain shipped for Issue
// #277, with real SFTP/cloud execution wired in for #450/#459) previously
// had ZERO test coverage. This file closes that gap.
//
// `@testable import ConverterEngine` is used here (rather than the plain
// `import ConverterEngine` most of `ConverterEngineTests` uses — see the
// policy note at the top of `ConverterEngineTests.swift`) for two things
// that are not part of the public API:
//   1. `PostEncodeActionChain.execute(inputURL:outputURL:success:actionExecutor:)`
//      — an internal test seam added alongside this file so the chain's
//      ordering / skip / error-aggregation logic can be exercised without
//      spawning real processes (`scp`/`curl`/`osascript`/`zsh`) or hitting
//      the network (`WebhookSender`/`CloudUploadExecutor`). The public,
//      3-argument `execute(inputURL:outputURL:success:)` is unchanged and
//      always delegates to this seam with `actionExecutor: nil`.
//   2. `PostEncodeActionChain.substituteVariables(in:inputURL:outputURL:profile:status:)`
//      — a pure string-substitution helper, bumped from `private` to the
//      default internal access level so it can be asserted on directly
//      instead of only observable through a real shell/notification
//      process.
// Everything else below (config resolution, `ActionError` descriptions,
// `PostEncodeActionType`/`PostEncodeAction` Codable round trips) is
// exercised through the public API only, matching the house style
// `CloudUploadExecutorTests.swift` documents: real behaviour, no
// fabricated network/process activity.
// ---------------------------------------------------------------------------

import XCTest
@testable import ConverterEngine

final class PostEncodeActionsTests: XCTestCase {

    // MARK: - Fixtures

    private let inputURL = URL(fileURLWithPath: "/tmp/post-encode-actions-tests-input.mov")
    private let outputURL = URL(fileURLWithPath: "/tmp/post-encode-actions-tests-output.mp4")

    // MARK: - (a) ActionError.errorDescription

    func test_actionError_shellScriptFailed_errorDescription() {
        let error = PostEncodeActionChain.ActionError.shellScriptFailed(
            exitCode: 2,
            output: "command not found"
        )
        XCTAssertEqual(
            error.errorDescription,
            "Shell script exited with code 2: command not found"
        )
    }

    func test_actionError_unsupportedAction_errorDescription() {
        let error = PostEncodeActionChain.ActionError.unsupportedAction(.webhook)
        XCTAssertEqual(
            error.errorDescription,
            "Action type 'webhook' is not yet supported."
        )
    }

    func test_actionError_missingConfig_errorDescription() {
        let error = PostEncodeActionChain.ActionError.missingConfig(
            key: "url",
            actionName: "Notify Slack"
        )
        XCTAssertEqual(
            error.errorDescription,
            "Action 'Notify Slack' is missing required config key 'url'."
        )
    }

    func test_actionError_uploadFailed_errorDescription() {
        let error = PostEncodeActionChain.ActionError.uploadFailed(
            actionName: "Upload to S3",
            message: "connection refused"
        )
        XCTAssertEqual(
            error.errorDescription,
            "Action 'Upload to S3' upload failed: connection refused"
        )
    }

    // MARK: - (b) Config resolution: missing profile never silently succeeds

    /// A `.uploadSFTP` action referencing a profile ID that has never been
    /// saved must throw a real `ActionError.missingConfig` — never silently
    /// return as if it had succeeded. Exercised entirely through the public
    /// `execute(inputURL:outputURL:success:)` API: `SFTPProfileStore.profile(
    /// withID:)` reads a fresh, unused `UserDefaults` key
    /// (`SFTPProfileStore.userDefaultsKey`), so a freshly-minted random
    /// `UUID` is guaranteed not to resolve to a saved profile without any
    /// special test isolation.
    func test_uploadSFTP_missingProfile_throwsMissingConfig_neverSilentlySucceeds() async {
        let action = PostEncodeAction(
            type: .uploadSFTP,
            name: "Nightly SFTP Upload",
            config: ["sftpProfileID": UUID().uuidString]
        )
        let chain = PostEncodeActionChain(actions: [action])

        do {
            try await chain.execute(inputURL: inputURL, outputURL: outputURL, success: true)
            XCTFail("Expected a missing-profile action to throw, never silently succeed.")
        } catch let error as PostEncodeActionChain.ActionError {
            guard case .missingConfig(let key, let actionName) = error else {
                XCTFail("Expected .missingConfig, got \(error)")
                return
            }
            XCTAssertEqual(key, "sftpProfileID")
            XCTAssertEqual(actionName, "Nightly SFTP Upload")
        } catch {
            XCTFail("Expected PostEncodeActionChain.ActionError, got \(error)")
        }
    }

    /// Mirrors the SFTP case above for `.uploadCloud` — a `cloudProfileID`
    /// that resolves to no saved `CloudStorageConfig` must throw, never
    /// fabricate success.
    func test_uploadCloud_missingProfile_throwsMissingConfig_neverSilentlySucceeds() async {
        let action = PostEncodeAction(
            type: .uploadCloud,
            name: "Nightly Cloud Upload",
            config: ["cloudProfileID": UUID().uuidString]
        )
        let chain = PostEncodeActionChain(actions: [action])

        do {
            try await chain.execute(inputURL: inputURL, outputURL: outputURL, success: true)
            XCTFail("Expected a missing-profile action to throw, never silently succeed.")
        } catch let error as PostEncodeActionChain.ActionError {
            guard case .missingConfig(let key, let actionName) = error else {
                XCTFail("Expected .missingConfig, got \(error)")
                return
            }
            XCTAssertEqual(key, "cloudProfileID")
            XCTAssertEqual(actionName, "Nightly Cloud Upload")
        } catch {
            XCTFail("Expected PostEncodeActionChain.ActionError, got \(error)")
        }
    }

    // MARK: - (c) Chain runner: ordering, skip rules, error aggregation

    /// Thread-safe call-order recorder for the injected `actionExecutor`
    /// closure below. `@unchecked Sendable`: every access happens under
    /// `lock`, mirroring the established pattern documented on
    /// `SFTPUploadIOState` (`SFTPUploader.swift`) and `MockURLProtocol`
    /// (`CloudUploadExecutorTests.swift`) elsewhere in this codebase.
    private final class ActionCallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var calls_: [String] = []
        private var successFlags_: [Bool] = []

        var calls: [String] {
            lock.lock(); defer { lock.unlock() }
            return calls_
        }

        var successFlags: [Bool] {
            lock.lock(); defer { lock.unlock() }
            return successFlags_
        }

        func record(_ name: String, success: Bool) {
            lock.lock(); defer { lock.unlock() }
            calls_.append(name)
            successFlags_.append(success)
        }
    }

    private struct BoomError: Error {}

    /// The chain's documented behaviour (see `execute`'s doc comment) is
    /// "continue on failure, surface the first error" — NOT abort-on-first-
    /// failure. This test pins that real, shipped behaviour: every enabled
    /// action still runs, in order, even after an earlier one throws.
    func test_execute_runsEveryEnabledActionInOrder_andDoesNotAbortOnFailure() async throws {
        let recorder = ActionCallRecorder()
        let actionA = PostEncodeAction(type: .openInFinder, name: "A")
        let actionB = PostEncodeAction(type: .openInFinder, name: "B")
        let actionC = PostEncodeAction(type: .openInFinder, name: "C")
        let chain = PostEncodeActionChain(actions: [actionA, actionB, actionC])

        do {
            try await chain.execute(
                inputURL: inputURL,
                outputURL: outputURL,
                success: true,
                actionExecutor: { action, success in
                    recorder.record(action.name, success: success)
                    if action.name == "B" {
                        throw BoomError()
                    }
                }
            )
            XCTFail("Expected B's error to propagate.")
        } catch is BoomError {
            // Expected.
        }

        XCTAssertEqual(
            recorder.calls, ["A", "B", "C"],
            "Every enabled action must run, in array order, even after B fails — "
                + "the chain collects the first error and keeps going rather than aborting."
        )
    }

    /// Two actions fail; the FIRST one's error is what must surface, not
    /// the last (`execute`'s doc comment: "Throws: The first error
    /// encountered during execution").
    func test_execute_throwsFirstErrorEncountered_notLast() async {
        struct NamedError: Error { let label: String }
        let actionA = PostEncodeAction(type: .openInFinder, name: "A")
        let actionB = PostEncodeAction(type: .openInFinder, name: "B")
        let chain = PostEncodeActionChain(actions: [actionA, actionB])

        do {
            try await chain.execute(
                inputURL: inputURL,
                outputURL: outputURL,
                success: true,
                actionExecutor: { action, _ in
                    throw NamedError(label: action.name)
                }
            )
            XCTFail("Expected an error to propagate.")
        } catch let error as NamedError {
            XCTAssertEqual(
                error.label, "A",
                "The FIRST action's error must surface even though B also failed."
            )
        } catch {
            XCTFail("Expected NamedError, got \(error)")
        }
    }

    func test_execute_skipsDisabledActions() async throws {
        let recorder = ActionCallRecorder()
        let disabled = PostEncodeAction(type: .openInFinder, name: "disabled", isEnabled: false)
        let enabled = PostEncodeAction(type: .openInFinder, name: "enabled", isEnabled: true)
        let chain = PostEncodeActionChain(actions: [disabled, enabled])

        try await chain.execute(
            inputURL: inputURL,
            outputURL: outputURL,
            success: true,
            actionExecutor: { action, success in
                recorder.record(action.name, success: success)
            }
        )

        XCTAssertEqual(recorder.calls, ["enabled"])
    }

    /// On a failed encode, only actions with `runOnFailure == true` may
    /// run; the rest must be skipped.
    func test_execute_onFailedJob_runsOnlyRunOnFailureActions() async throws {
        let recorder = ActionCallRecorder()
        let normal = PostEncodeAction(type: .openInFinder, name: "normal", runOnFailure: false)
        let cleanup = PostEncodeAction(type: .openInFinder, name: "cleanup", runOnFailure: true)
        let chain = PostEncodeActionChain(actions: [normal, cleanup])

        try await chain.execute(
            inputURL: inputURL,
            outputURL: outputURL,
            success: false,
            actionExecutor: { action, success in
                recorder.record(action.name, success: success)
            }
        )

        XCTAssertEqual(recorder.calls, ["cleanup"])
        XCTAssertEqual(recorder.successFlags, [false])
    }

    /// On a successful encode, every enabled action runs regardless of its
    /// `runOnFailure` flag — that flag only restricts execution on failure.
    func test_execute_onSuccessfulJob_runsRegardlessOfRunOnFailureFlag() async throws {
        let recorder = ActionCallRecorder()
        let normal = PostEncodeAction(type: .openInFinder, name: "normal", runOnFailure: false)
        let alsoOnFailure = PostEncodeAction(type: .openInFinder, name: "always", runOnFailure: true)
        let chain = PostEncodeActionChain(actions: [normal, alsoOnFailure])

        try await chain.execute(
            inputURL: inputURL,
            outputURL: outputURL,
            success: true,
            actionExecutor: { action, success in
                recorder.record(action.name, success: success)
            }
        )

        XCTAssertEqual(recorder.calls, ["normal", "always"])
        XCTAssertEqual(recorder.successFlags, [true, true])
    }

    // MARK: - (d) substituteVariables — pure helper

    func test_substituteVariables_replacesAllFourPlaceholders() {
        let chain = PostEncodeActionChain()
        let result = chain.substituteVariables(
            in: "in={input} out={output} profile={profile} status={status}",
            inputURL: URL(fileURLWithPath: "/Users/x/in.mov"),
            outputURL: URL(fileURLWithPath: "/Users/x/out.mp4"),
            profile: "My Profile",
            status: "success"
        )
        XCTAssertEqual(
            result,
            "in=/Users/x/in.mov out=/Users/x/out.mp4 profile=My Profile status=success"
        )
    }

    func test_substituteVariables_leavesUnrecognisedPlaceholdersUntouched() {
        let chain = PostEncodeActionChain()
        let result = chain.substituteVariables(
            in: "{unknown} {input}",
            inputURL: URL(fileURLWithPath: "/a/in"),
            outputURL: URL(fileURLWithPath: "/b/out"),
            profile: "",
            status: "failure"
        )
        XCTAssertEqual(result, "{unknown} /a/in")
    }

    func test_substituteVariables_statusReflectsFailure() {
        let chain = PostEncodeActionChain()
        let result = chain.substituteVariables(
            in: "{status}",
            inputURL: URL(fileURLWithPath: "/a"),
            outputURL: URL(fileURLWithPath: "/b"),
            profile: "p",
            status: "failure"
        )
        XCTAssertEqual(result, "failure")
    }

    // MARK: - (e) Codable round trips

    func test_postEncodeActionType_codableRoundTrip_allCases() throws {
        for type in PostEncodeActionType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(PostEncodeActionType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    func test_postEncodeAction_codableRoundTrip_preservesConfigAndFlags() throws {
        let original = PostEncodeAction(
            type: .uploadSFTP,
            name: "Upload nightly build",
            config: ["sftpProfileID": UUID().uuidString, "extra": "value"],
            isEnabled: false,
            runOnFailure: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PostEncodeAction.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.config, original.config)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
        XCTAssertEqual(decoded.runOnFailure, original.runOnFailure)
    }

    func test_postEncodeActionChain_codableRoundTrip_preservesActionOrder() throws {
        let chain = PostEncodeActionChain(actions: [
            PostEncodeAction(type: .moveSourceToTrash, name: "Trash"),
            PostEncodeAction(type: .openInFinder, name: "Reveal"),
            PostEncodeAction(type: .sendNotification, name: "Notify")
        ])

        let data = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode(PostEncodeActionChain.self, from: data)

        XCTAssertEqual(decoded.actions.map(\.name), ["Trash", "Reveal", "Notify"])
        XCTAssertEqual(decoded.actions.map(\.type), [.moveSourceToTrash, .openInFinder, .sendNotification])
    }
}
