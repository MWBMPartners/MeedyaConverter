// ============================================================================
// MeedyaConverter — EncodingPersistenceActors (Issue #286)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Two serialising actors that make the encoding queue's per-job completion
// side effects safe when more than one job can finish at once (Issue #286).
//
//   * `EncodingStatisticsRecorder` — statistics persistence. The store's
//     `addStatistics(_:)` is a load-append-rewrite of a single JSON file, so
//     two completions landing together used to lose one entry.
//   * `PostEncodeHookRunner` — post-encode action chains. The chain engine
//     itself is reentrant-safe, but the *user's* shell scripts and uploads
//     are not necessarily, so hooks are kept strictly one-at-a-time.
//
// Both are `actor`s rather than lock-protected classes because the work they
// serialise is blocking file / subprocess I/O that must not run on the
// `@MainActor`, and actor isolation gives that for free.
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - EncodingStatisticsRecorder
// ---------------------------------------------------------------------------
/// Serialises writes to the encoding statistics history.
///
/// ### The race this fixes
///
/// `EncodingStatisticsStore.addStatistics(_:)` appends to an in-memory
/// history and then rewrites the whole `encoding_history.json` atomically.
/// The store's own `NSLock` protects one *instance*; it does nothing across
/// instances. Both of `AppViewModel`'s completion paths used to construct a
/// brand-new store per write, so two jobs finishing at nearly the same
/// moment would each load the same baseline, each append their own entry,
/// and the second write would clobber the first — silently dropping a job
/// from the Dashboard's success-rate maths.
///
/// Routing every write through one actor makes load-append-rewrite
/// atomic with respect to other writes, because the actor admits one call
/// at a time and `record(_:)` contains no suspension point.
///
/// ### Why a fresh store per write
///
/// The recorder deliberately does *not* hold a long-lived store. A store
/// snapshots the file at `init()`, and `DashboardView` clears the history
/// through its own separate instance; a cached in-memory history here would
/// happily resurrect everything the user just cleared on the next write.
/// Constructing the store inside the isolated method preserves the
/// read-fresh-then-append semantics the sequential code already had, while
/// the actor supplies the mutual exclusion it lacked. The history is capped
/// at 100 entries, so the re-read costs nothing meaningful.
public actor EncodingStatisticsRecorder {

    /// Directory holding `encoding_history.json`, or `nil` for the store's
    /// default location. Injectable so tests can point at a temp directory.
    private let directory: URL?

    /// Maximum retained entries, passed straight through to the store.
    private let maxHistoryCount: Int

    /// Create a recorder.
    ///
    /// - Parameters:
    ///   - directory: Storage directory, or `nil` for the default
    ///     (`~/.config/MeedyaConverter/Statistics`).
    ///   - maxHistoryCount: Maximum entries retained on disk.
    public init(directory: URL? = nil, maxHistoryCount: Int = 100) {
        self.directory = directory
        self.maxHistoryCount = maxHistoryCount
    }

    /// Append one job's statistics to the persisted history.
    ///
    /// Blocking disk I/O, executed on the actor's executor — never on the
    /// `@MainActor`.
    public func record(_ statistics: EncodingStatistics) {
        EncodingStatisticsStore(
            directory: directory,
            maxHistoryCount: maxHistoryCount
        ).addStatistics(statistics)
    }

    /// The persisted history, newest first. Reads through the same
    /// serialisation point as `record(_:)`, so a caller that awaits this
    /// after awaiting its writes is guaranteed to see them.
    public func allStatistics() -> [EncodingStatistics] {
        EncodingStatisticsStore(
            directory: directory,
            maxHistoryCount: maxHistoryCount
        ).allStatistics
    }
}

// ---------------------------------------------------------------------------
// MARK: - PostEncodeHookRunner
// ---------------------------------------------------------------------------
/// Runs post-encode action chains strictly one at a time.
///
/// `PostEncodeActionChain` is a `Sendable` value type and `execute` is
/// itself safe to call concurrently, so this actor is not protecting the
/// chain — it is protecting the *user's* actions. A chain typically ends in
/// a shell script, an scp/rsync upload, or a move-to-trash; scripts written
/// against a strictly sequential queue routinely assume they are the only
/// copy running (fixed temp paths, lock files, sequential uploads).
/// Serialising execution keeps that contract intact no matter how many
/// encodes run at once: hooks fire in job-completion order, one after
/// another.
///
/// Execution remains fire-and-forget from the job's point of view — the
/// caller kicks off a `Task` and does not await it — so a slow hook delays
/// only later hooks, never the encoding queue.
///
/// ### Why actor isolation alone is NOT enough here
///
/// Being an `actor` does **not** by itself serialise this work, and an
/// earlier version of this type got that wrong. Swift actors are
/// *reentrant*: an isolated method that suspends releases the actor, and
/// another call may enter while the first is still awaiting. Since the only
/// thing `run` does is `await chain.execute(...)` — a `nonisolated async`
/// call — the actor would be released immediately on entry, and two jobs
/// finishing together would run their chains in parallel anyway. The
/// mutual exclusion would have been entirely imaginary while the doc
/// comment promised it.
///
/// Real serialisation therefore comes from chaining each execution onto the
/// previous one through a stored `tail` task: each caller captures the
/// current tail, awaits it, then runs. Because `tail` is only read and
/// written in actor-isolated code with no suspension between the read and
/// the write, the chain cannot fork. That also preserves FIFO order, which
/// is the property the user's scripts actually depend on.
public actor PostEncodeHookRunner {

    /// The most recently queued execution. Each new run awaits this before
    /// starting, then becomes the new tail.
    ///
    /// Read and reassigned without an intervening `await`, so two concurrent
    /// callers cannot both observe the same predecessor.
    private var tail: Task<Void, Never>?

    public init() {}

    /// Queue one chain behind any chain already queued or running.
    ///
    /// Returns as soon as the work is *enqueued*, not when it completes —
    /// awaiting the returned position would reintroduce the coupling between
    /// hook duration and queue throughput this type exists to avoid. Call
    /// `drain()` if you need to wait for everything to finish.
    ///
    /// Errors are swallowed, matching the fire-and-forget behaviour of the
    /// call sites this replaces: a failing hook must never surface as a
    /// second, unrelated error on top of the encode result already handled.
    ///
    /// - Parameters:
    ///   - chain: The action chain to run.
    ///   - inputURL: The job's source file.
    ///   - outputURL: The job's output file.
    ///   - success: Whether the encode succeeded. `execute` uses this to
    ///     skip actions that lack `runOnFailure`.
    public func run(
        chain: PostEncodeActionChain,
        inputURL: URL,
        outputURL: URL,
        success: Bool
    ) {
        let predecessor = tail
        tail = Task {
            // Wait for the previous chain. `Task<Void, Never>` cannot throw
            // and is never cancelled by this type, so this simply orders the
            // executions.
            await predecessor?.value
            try? await chain.execute(
                inputURL: inputURL,
                outputURL: outputURL,
                success: success
            )
        }
    }

    /// Wait for every queued chain to finish.
    ///
    /// Intended for tests and for an orderly shutdown; the encode paths
    /// deliberately do not call it.
    public func drain() async {
        await tail?.value
    }
}
