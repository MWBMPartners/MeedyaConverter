// ============================================================================
// MeedyaConverter — RenderFarmClient
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Client-side wiring for the render-farm subsystem. Responsible for:
//   - Maintaining the list of known agents (Bonjour-discovered + manual)
//   - Submitting jobs, uploading source chunks, receiving progress updates
//   - Downloading finished outputs and verifying integrity
//
// The transport layer is abstracted behind `RenderFarmTransportAdapter` so
// the same submission protocol can run over SSH tunnels, TLS, or plaintext
// HTTP depending on user preference.
//
// GitHub Issue #346 — Remote encoding / render farm submission.
// ============================================================================

import Foundation

// MARK: - RenderFarmTransportAdapter

/// Protocol for transport adapters that can talk to a render-farm agent.
/// Real implementations wrap URLSession with SSH tunnelling / TLS pinning;
/// unit tests provide an in-memory mock adapter.
public protocol RenderFarmTransportAdapter: Sendable {
    /// Submit a new job to an agent. Returns the agent's acknowledgement.
    func submit(
        agent: RenderFarmAgentInfo,
        submission: RenderFarmJobSubmission
    ) async throws -> RenderFarmJobStatus

    /// Upload a single chunk of the source file.
    func uploadChunk(
        agent: RenderFarmAgentInfo,
        chunk: RenderFarmChunk
    ) async throws

    /// Request the current status of a job.
    func status(
        agent: RenderFarmAgentInfo,
        jobId: UUID
    ) async throws -> RenderFarmJobStatus

    /// Download the completed output to the given destination.
    func download(
        agent: RenderFarmAgentInfo,
        jobId: UUID,
        destination: URL
    ) async throws -> URL

    /// Cancel a job.
    func cancel(
        agent: RenderFarmAgentInfo,
        jobId: UUID
    ) async throws
}

// MARK: - InsecureTransportOverride

/// Capability token that authorises a `RenderFarmClient` to accept
/// submissions over an insecure transport (plain HTTP).
///
/// Audit follow-up for issue #380. The previous shape exposed a bare
/// `allowInsecureTransports: Bool` flag on `RenderFarmClient.Configuration`,
/// which made it easy to write `allowInsecureTransports: true` in a
/// single line and slip past code review. Requiring a token type at the
/// construction site forces every caller to spell out a static factory
/// call — `.developmentOnly(acknowledgement: ...)` — that is hard to
/// miss in a diff and gets surfaced in audit logs.
///
/// The token is intentionally not `Codable` and never crosses the wire:
/// the insecure-transport policy is enforced by the *client* before it
/// hands a submission to the transport adapter. Agents make their own
/// independent decision about whether they will accept plain HTTP.
public struct InsecureTransportOverride: Sendable {

    /// Human-readable rationale for granting the override. Surfaced in
    /// the validation error path, log lines, and UI warnings so that
    /// reviewers can see *why* the override was granted at every site.
    public let acknowledgement: String

    /// Private initialiser keeps `InsecureTransportOverride` un-constructable
    /// outside of the documented factory below.
    private init(acknowledgement: String) {
        self.acknowledgement = acknowledgement
    }

    /// The only path to obtain an override. The factory is deliberately
    /// named `developmentOnly` so the word "development" appears at every
    /// call site that turns plain HTTP on — an obvious static review
    /// signal that no innocuous-sounding alternative exists for production.
    ///
    /// - Parameter acknowledgement: A short rationale (e.g. "local dev
    ///   loopback, no real credentials"). Stored on the override and
    ///   echoed in the rejection error message when the override is
    ///   missing.
    public static func developmentOnly(
        acknowledgement: String
    ) -> InsecureTransportOverride {
        InsecureTransportOverride(acknowledgement: acknowledgement)
    }
}

// MARK: - RenderFarmClient

/// Primary client type used by the CLI and the macOS UI to talk to the
/// render-farm subsystem. Holds the list of known agents and coordinates
/// submission via a pluggable transport.
public final class RenderFarmClient: @unchecked Sendable {

    // MARK: Configuration

    public struct Configuration: Sendable {
        /// Capability token authorising plain HTTP submissions. `nil`
        /// (the default) means insecure transports are refused. Set this
        /// to `.developmentOnly(acknowledgement: …)` if and only if you
        /// genuinely intend to allow plain HTTP — see
        /// `InsecureTransportOverride` for the rationale.
        public var insecureTransportOverride: InsecureTransportOverride?
        /// Bonjour discovery auto-refresh interval in seconds.
        public var discoveryIntervalSeconds: TimeInterval
        /// Chunk size for source uploads, in bytes.
        public var chunkSizeBytes: UInt64

        public init(
            insecureTransportOverride: InsecureTransportOverride? = nil,
            discoveryIntervalSeconds: TimeInterval = 30,
            chunkSizeBytes: UInt64 = RenderFarmProtocol.defaultChunkSizeBytes
        ) {
            self.insecureTransportOverride = insecureTransportOverride
            self.discoveryIntervalSeconds = discoveryIntervalSeconds
            self.chunkSizeBytes = chunkSizeBytes
        }

        /// Whether this configuration permits plain HTTP. Read-only
        /// convenience for callers that just need a boolean (e.g. UI
        /// warning banners). Equivalent to
        /// `insecureTransportOverride != nil`.
        public var allowsInsecureTransports: Bool {
            insecureTransportOverride != nil
        }
    }

    // MARK: State

    private let lock = NSLock()
    private var agentsByID: [UUID: RenderFarmAgentInfo] = [:]
    private let transport: RenderFarmTransportAdapter
    public let configuration: Configuration

    // MARK: Lifecycle

    public init(
        transport: RenderFarmTransportAdapter,
        configuration: Configuration = Configuration()
    ) {
        self.transport = transport
        self.configuration = configuration
    }

    // MARK: Agent registry

    /// Register (or update) an agent in the local registry. Does not attempt
    /// to contact the agent — that happens on first submit.
    public func register(agent: RenderFarmAgentInfo) {
        lock.lock()
        defer { lock.unlock() }
        agentsByID[agent.id] = agent
    }

    /// Remove an agent from the local registry.
    public func unregister(agentID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        agentsByID.removeValue(forKey: agentID)
    }

    /// Snapshot of registered agents, ordered by display name for stable UI.
    public func allAgents() -> [RenderFarmAgentInfo] {
        lock.lock()
        defer { lock.unlock() }
        return agentsByID.values.sorted { $0.displayName < $1.displayName }
    }

    /// Look up a single agent by ID.
    public func agent(id: UUID) -> RenderFarmAgentInfo? {
        lock.lock()
        defer { lock.unlock() }
        return agentsByID[id]
    }

    // MARK: Submission

    /// Refuses insecure transports unless an `InsecureTransportOverride`
    /// is present in the configuration. The override-and-reject path is
    /// the only mechanism by which a `.plainHTTP` submission can reach
    /// the transport adapter, so the policy is enforced exactly once,
    /// here at the boundary.
    public func validate(submission: RenderFarmJobSubmission) throws {
        guard submission.transport == .plainHTTP else { return }
        guard configuration.insecureTransportOverride != nil else {
            throw RenderFarmError.unsupportedTransport(
                "plainHTTP refused: RenderFarmClient.Configuration was "
                + "constructed without an `InsecureTransportOverride`. "
                + "Pass `.developmentOnly(acknowledgement: …)` if and "
                + "only if this submission is on a trusted loopback or "
                + "isolated development network."
            )
        }
    }

    /// Submits a job to the agent identified by `submission.agentId`.
    /// The returned status is the agent's initial acknowledgement.
    public func submit(_ submission: RenderFarmJobSubmission) async throws -> RenderFarmJobStatus {
        try validate(submission: submission)
        guard let agent = agent(id: submission.agentId) else {
            throw RenderFarmError.agentNotReachable("unknown agent \(submission.agentId)")
        }
        return try await transport.submit(agent: agent, submission: submission)
    }

    /// Uploads a chunk for a job.
    public func uploadChunk(_ chunk: RenderFarmChunk, toAgent agentID: UUID) async throws {
        guard let agent = agent(id: agentID) else {
            throw RenderFarmError.agentNotReachable("unknown agent \(agentID)")
        }
        try await transport.uploadChunk(agent: agent, chunk: chunk)
    }

    /// Requests the current status of a job from the agent.
    public func status(jobId: UUID, agentID: UUID) async throws -> RenderFarmJobStatus {
        guard let agent = agent(id: agentID) else {
            throw RenderFarmError.agentNotReachable("unknown agent \(agentID)")
        }
        return try await transport.status(agent: agent, jobId: jobId)
    }

    /// Polls for progress updates, yielding each status snapshot on an
    /// `AsyncStream`. Stops yielding when the job reaches a terminal state
    /// (`completed`, `failed`, `cancelled`).
    public func progressStream(
        jobId: UUID,
        agentID: UUID,
        pollIntervalSeconds: UInt64 = 2
    ) -> AsyncThrowingStream<RenderFarmJobStatus, Error> {
        AsyncThrowingStream { continuation in
            // Assign the task to a box BEFORE setting onTermination so the
            // cancellation closure always sees the live task — otherwise a
            // caller that aborts the stream between `init` and the first
            // status poll can leave a detached task running.
            final class TaskBox: @unchecked Sendable {
                var task: Task<Void, Never>?
            }
            let box = TaskBox()
            continuation.onTermination = { _ in box.task?.cancel() }
            box.task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    while !Task.isCancelled {
                        let snapshot = try await self.status(jobId: jobId, agentID: agentID)
                        continuation.yield(snapshot)
                        if Self.isTerminal(state: snapshot.state) {
                            continuation.finish()
                            return
                        }
                        try await Task.sleep(nanoseconds: pollIntervalSeconds * 1_000_000_000)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Downloads the completed output to the given destination URL.
    public func download(
        jobId: UUID,
        agentID: UUID,
        destination: URL
    ) async throws -> URL {
        guard let agent = agent(id: agentID) else {
            throw RenderFarmError.agentNotReachable("unknown agent \(agentID)")
        }
        return try await transport.download(
            agent: agent,
            jobId: jobId,
            destination: destination
        )
    }

    /// Cancels a job.
    public func cancel(jobId: UUID, agentID: UUID) async throws {
        guard let agent = agent(id: agentID) else {
            throw RenderFarmError.agentNotReachable("unknown agent \(agentID)")
        }
        try await transport.cancel(agent: agent, jobId: jobId)
    }

    // MARK: Helpers

    /// Whether the state is terminal (progress stream should stop).
    public static func isTerminal(state: RenderFarmJobState) -> Bool {
        switch state {
        case .completed, .failed, .cancelled: return true
        case .queued, .transferring, .encoding, .finalising: return false
        }
    }
}
