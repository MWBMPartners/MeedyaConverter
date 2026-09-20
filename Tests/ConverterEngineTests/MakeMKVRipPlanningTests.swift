// ============================================================================
// MeedyaConverter — MakeMKVRipPlanningTests (Issue #503, slice 4b)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Exercises the pure rip-planning helpers behind the GUI rip flow: progress
// folding, default title selection, selector building, aggregate-fraction
// clamping, title summary formatting, and the pinned plain-English failure
// text. Everything under test is a pure value type/namespace — no process,
// no `UserDefaults`, nothing to isolate between tests, and every test here
// is independently safe under `swift test --parallel`.
// ============================================================================

import XCTest
import ConverterEngine

final class MakeMKVRipPlanningTests: XCTestCase {

    // MARK: - Fixture helpers

    /// A minimal `MakeMKVTitle` with only the attributes a given test needs.
    private func makeTitle(
        index: Int,
        duration: String? = nil,
        sizeBytes: Int64? = nil
    ) -> MakeMKVTitle {
        var attributes: [MakeMKVAttribute] = []
        if let duration {
            attributes.append(MakeMKVAttribute(id: MakeMKVAttributeID.duration.rawValue, code: 0, value: duration))
        }
        if let sizeBytes {
            attributes.append(MakeMKVAttribute(id: MakeMKVAttributeID.diskSizeBytes.rawValue, code: 0, value: String(sizeBytes)))
        }
        return MakeMKVTitle(index: index, attributes: attributes, streams: [])
    }

    // MARK: - MakeMKVRipProgressTracker

    func test_tracker_startsEmpty() {
        let tracker = MakeMKVRipProgressTracker()
        XCTAssertNil(tracker.overallCaption)
        XCTAssertNil(tracker.currentCaption)
        XCTAssertNil(tracker.overallFraction)
        XCTAssertNil(tracker.currentFraction)
        XCTAssertNil(tracker.lastMessage)
    }

    func test_tracker_recordsCaptionsFractionsAndMessages() {
        var tracker = MakeMKVRipProgressTracker()
        tracker.record(.progress(.totalTitle(code: 5017, id: 0, name: "Saving all titles")))
        tracker.record(.progress(.currentTitle(code: 5018, id: 0, name: "Analyzing")))
        tracker.record(.progress(.values(current: 16384, total: 32768, max: 65536)))
        tracker.record(.message(MakeMKVMessage(code: 1, flags: 0, text: "Hello", rawFormat: "Hello", parameters: [])))

        XCTAssertEqual(tracker.overallCaption, "Saving all titles")
        XCTAssertEqual(tracker.currentCaption, "Analyzing")
        XCTAssertEqual(tracker.overallFraction, 0.5)
        XCTAssertEqual(tracker.currentFraction, 0.25)
        XCTAssertEqual(tracker.lastMessage, "Hello")
    }

    func test_tracker_unusableValuesKeepThePreviousFraction() {
        var tracker = MakeMKVRipProgressTracker()
        // Power-of-two fractions so the equality checks below are exact
        // under IEEE 754 double arithmetic, not just "close enough".
        tracker.record(.progress(.values(current: 16384, total: 49152, max: 65536)))
        XCTAssertEqual(tracker.overallFraction, 0.75)
        XCTAssertEqual(tracker.currentFraction, 0.25)

        // max <= 0 is unusable (see MakeMKVProgressEvent.totalFraction/
        // currentFraction) — must not reset the fraction to nil.
        tracker.record(.progress(.values(current: 1, total: 2, max: 0)))
        XCTAssertEqual(tracker.overallFraction, 0.75)
        XCTAssertEqual(tracker.currentFraction, 0.25)
    }

    func test_tracker_overwritesCaptionsOnEachEvent() {
        var tracker = MakeMKVRipProgressTracker()
        tracker.record(.progress(.currentTitle(code: 1, id: 0, name: "First")))
        tracker.record(.progress(.currentTitle(code: 1, id: 1, name: "Second")))
        XCTAssertEqual(tracker.currentCaption, "Second")
    }

    // MARK: - defaultSelection

    func test_defaultSelection_emptyTitleListIsEmpty() {
        XCTAssertEqual(MakeMKVRipPlanning.defaultSelection(for: []), [])
    }

    func test_defaultSelection_loneTitleAlwaysSelectedEvenWithoutDuration() {
        let title = makeTitle(index: 3)
        XCTAssertEqual(MakeMKVRipPlanning.defaultSelection(for: [title]), [3])
    }

    func test_defaultSelection_picksGreatestDuration() {
        let a = makeTitle(index: 0, duration: "0:10:00")
        let b = makeTitle(index: 1, duration: "1:57:21")
        let c = makeTitle(index: 2, duration: "0:05:00")
        XCTAssertEqual(MakeMKVRipPlanning.defaultSelection(for: [a, b, c]), [1])
    }

    func test_defaultSelection_tieBrokenByGreatestSize() {
        let a = makeTitle(index: 0, duration: "1:00:00", sizeBytes: 1_000)
        let b = makeTitle(index: 1, duration: "1:00:00", sizeBytes: 5_000)
        XCTAssertEqual(MakeMKVRipPlanning.defaultSelection(for: [a, b]), [1])
    }

    func test_defaultSelection_remainingTieBrokenByLowestIndex() {
        let a = makeTitle(index: 2, duration: "1:00:00", sizeBytes: 5_000)
        let b = makeTitle(index: 0, duration: "1:00:00", sizeBytes: 5_000)
        XCTAssertEqual(MakeMKVRipPlanning.defaultSelection(for: [a, b]), [0])
    }

    func test_defaultSelection_emptyWhenNoTitleHasAParseableDuration() {
        let a = makeTitle(index: 0)
        let b = makeTitle(index: 1)
        XCTAssertEqual(MakeMKVRipPlanning.defaultSelection(for: [a, b]), [], "never guess when nothing has a usable duration")
    }

    func test_defaultSelection_ignoresTitlesWithoutADurationWhenOthersHaveOne() {
        let a = makeTitle(index: 0)
        let b = makeTitle(index: 1, duration: "0:30:00")
        XCTAssertEqual(MakeMKVRipPlanning.defaultSelection(for: [a, b]), [1])
    }

    // MARK: - selectors(forSelected:allTitleIndices:)

    func test_selectors_emptyWhenNothingSelected() {
        XCTAssertEqual(MakeMKVRipPlanning.selectors(forSelected: [], allTitleIndices: [0, 1, 2]), [])
    }

    func test_selectors_allWhenEveryListedTitleIsSelected() {
        XCTAssertEqual(MakeMKVRipPlanning.selectors(forSelected: [0, 1, 2], allTitleIndices: [0, 1, 2]), [.all])
    }

    func test_selectors_allIgnoresOrdering() {
        XCTAssertEqual(MakeMKVRipPlanning.selectors(forSelected: [2, 0, 1], allTitleIndices: [1, 0, 2]), [.all])
    }

    func test_selectors_ascendingIndicesForASubset() {
        XCTAssertEqual(
            MakeMKVRipPlanning.selectors(forSelected: [2, 0], allTitleIndices: [0, 1, 2]),
            [.index(0), .index(2)]
        )
    }

    func test_selectors_singleTitleSelected() {
        XCTAssertEqual(MakeMKVRipPlanning.selectors(forSelected: [1], allTitleIndices: [0, 1, 2]), [.index(1)])
    }

    // MARK: - aggregateFraction

    func test_aggregateFraction_zeroTotalRunsIsZero() {
        XCTAssertEqual(MakeMKVRipPlanning.aggregateFraction(completedRuns: 0, totalRuns: 0, currentRunFraction: 0.5), 0)
    }

    func test_aggregateFraction_midRunCombinesCompletedAndCurrent() {
        // 1 of 2 runs done, current run 50% through → 0.5 + (0.5 / 2) = 0.75
        XCTAssertEqual(MakeMKVRipPlanning.aggregateFraction(completedRuns: 1, totalRuns: 2, currentRunFraction: 0.5), 0.75)
    }

    func test_aggregateFraction_nilCurrentFractionTreatedAsZero() {
        XCTAssertEqual(MakeMKVRipPlanning.aggregateFraction(completedRuns: 1, totalRuns: 2, currentRunFraction: nil), 0.5)
    }

    func test_aggregateFraction_clampsAboveOne() {
        XCTAssertEqual(MakeMKVRipPlanning.aggregateFraction(completedRuns: 3, totalRuns: 2, currentRunFraction: 1), 1)
    }

    func test_aggregateFraction_clampsBelowZero() {
        XCTAssertEqual(MakeMKVRipPlanning.aggregateFraction(completedRuns: -1, totalRuns: 2, currentRunFraction: nil), 0)
    }

    // MARK: - MakeMKVTitleSummary

    func test_summary_displayNamePrefersTitleName() {
        let title = MakeMKVTitle(index: 0, attributes: [
            MakeMKVAttribute(id: MakeMKVAttributeID.name.rawValue, code: 0, value: "Feature Film")
        ], streams: [])
        XCTAssertEqual(MakeMKVTitleSummary(title: title).displayName, "Feature Film")
    }

    func test_summary_displayNameFallsBackToSourceFileName() {
        let title = MakeMKVTitle(index: 2, attributes: [
            MakeMKVAttribute(id: MakeMKVAttributeID.sourceFileName.rawValue, code: 0, value: "00800.mpls")
        ], streams: [])
        XCTAssertEqual(MakeMKVTitleSummary(title: title).displayName, "00800.mpls")
    }

    func test_summary_displayNameFallsBackToOneBasedTitleNumber() {
        let title = MakeMKVTitle(index: 4, attributes: [], streams: [])
        XCTAssertEqual(MakeMKVTitleSummary(title: title).displayName, "Title 5")
    }

    func test_summary_durationTextPassesThroughDiscString() {
        let title = makeTitle(index: 0, duration: "1:57:21")
        XCTAssertEqual(MakeMKVTitleSummary(title: title).durationText, "1:57:21")
    }

    func test_summary_sizeTextPrefersMakeMKVsOwnText() {
        let title = MakeMKVTitle(index: 0, attributes: [
            MakeMKVAttribute(id: MakeMKVAttributeID.diskSize.rawValue, code: 0, value: "26.5 GB"),
            MakeMKVAttribute(id: MakeMKVAttributeID.diskSizeBytes.rawValue, code: 0, value: "999999999999")
        ], streams: [])
        XCTAssertEqual(MakeMKVTitleSummary(title: title).sizeText, "26.5 GB")
    }

    func test_summary_sizeTextFallsBackToFormattedBytes() {
        let title = makeTitle(index: 0, sizeBytes: 1_000_000_000)
        let summary = MakeMKVTitleSummary(title: title)
        XCTAssertNotNil(summary.sizeText)
        XCTAssertFalse(summary.sizeText?.isEmpty ?? true)
    }

    func test_summary_sizeTextNilWhenNeitherIsReported() {
        let title = MakeMKVTitle(index: 0, attributes: [], streams: [])
        XCTAssertNil(MakeMKVTitleSummary(title: title).sizeText)
    }

    func test_summary_chaptersTextSingularAndPlural() {
        let one = MakeMKVTitle(index: 0, attributes: [
            MakeMKVAttribute(id: MakeMKVAttributeID.chapterCount.rawValue, code: 0, value: "1")
        ], streams: [])
        XCTAssertEqual(MakeMKVTitleSummary(title: one).chaptersText, "1 chapter")

        let many = MakeMKVTitle(index: 0, attributes: [
            MakeMKVAttribute(id: MakeMKVAttributeID.chapterCount.rawValue, code: 0, value: "12")
        ], streams: [])
        XCTAssertEqual(MakeMKVTitleSummary(title: many).chaptersText, "12 chapters")
    }

    func test_summary_chaptersTextNilWhenAbsent() {
        let title = MakeMKVTitle(index: 0, attributes: [], streams: [])
        XCTAssertNil(MakeMKVTitleSummary(title: title).chaptersText)
    }

    func test_summary_streamsTextGroupsByTypeInFirstSeenOrder() {
        let streams = [
            MakeMKVStream(index: 0, attributes: [MakeMKVAttribute(id: MakeMKVAttributeID.type.rawValue, code: 0, value: "Video")]),
            MakeMKVStream(index: 1, attributes: [MakeMKVAttribute(id: MakeMKVAttributeID.type.rawValue, code: 0, value: "Audio")]),
            MakeMKVStream(index: 2, attributes: [MakeMKVAttribute(id: MakeMKVAttributeID.type.rawValue, code: 0, value: "Audio")]),
            MakeMKVStream(index: 3, attributes: [MakeMKVAttribute(id: MakeMKVAttributeID.type.rawValue, code: 0, value: "Subtitles")]),
        ]
        let title = MakeMKVTitle(index: 0, attributes: [], streams: streams)
        XCTAssertEqual(MakeMKVTitleSummary(title: title).streamsText, "1 Video, 2 Audio, 1 Subtitles")
    }

    func test_summary_streamsTextNilWhenNoStreams() {
        let title = MakeMKVTitle(index: 0, attributes: [], streams: [])
        XCTAssertNil(MakeMKVTitleSummary(title: title).streamsText)
    }

    // MARK: - failureSummary

    func test_failureSummary_cancellation() {
        XCTAssertEqual(MakeMKVRipPlanning.failureSummary(for: CancellationError()), "The rip was cancelled.")
    }

    func test_failureSummary_notConsented() {
        XCTAssertEqual(
            MakeMKVRipPlanning.failureSummary(for: MakeMKVExecutorError.notConsented),
            "MakeMKV is not turned on for this app yet. Turn it on and add your terms acknowledgement in Settings, then try again."
        )
    }

    func test_failureSummary_launchFailed() {
        XCTAssertEqual(
            MakeMKVRipPlanning.failureSummary(
                for: MakeMKVExecutorError.launchFailed(binaryPath: "/usr/local/bin/makemkvcon", reason: "no such file")
            ),
            "MakeMKV could not be started (/usr/local/bin/makemkvcon): no such file"
        )
    }

    func test_failureSummary_processFailureWithSnippet() {
        XCTAssertEqual(
            MakeMKVRipPlanning.failureSummary(for: MakeMKVExecutorError.processFailure(exitCode: 1, snippet: "Disc read error")),
            "MakeMKV stopped with an error: Disc read error."
        )
    }

    func test_failureSummary_processFailureWithoutSnippet() {
        XCTAssertEqual(
            MakeMKVRipPlanning.failureSummary(for: MakeMKVExecutorError.processFailure(exitCode: 2, snippet: "   ")),
            "MakeMKV stopped with an error (code 2)."
        )
    }

    func test_failureSummary_unknownErrorFallsBackToLocalizedDescription() {
        struct DummyError: LocalizedError {
            var errorDescription: String? { "boom" }
        }
        XCTAssertEqual(MakeMKVRipPlanning.failureSummary(for: DummyError()), "The rip failed: boom")
    }
}
