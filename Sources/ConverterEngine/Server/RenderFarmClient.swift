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

// MARK: - RenderFarmClient

/// Primary client type used by the CLI and the macOS UI to talk to the
/// render-farm subsystem. Holds the list of known agents and coordinates
/// submission via a pluggable transport.
public final class RenderFarmClient: @unchecked Sendable {

    // MARK: Configuration

    public struct Configuration: Sendable {
        /// Allow plaintext HTTP (discouraged; for local development only).
        public var allowInsecureTransports: Bool
        /// Bonjour discovery auto-refresh interval in seconds.
        public var discoveryIntervalSeconds: TimeInterval
        /// Chunk size for source uploads, in bytes.
        public var chunkSizeBytes: UInt64

        public init(
            allowInsecureTransports: Bool = false,
            discoveryIntervalSeconds: TimeInterval = 30,
            chunkSizeBytes: UInt64 = RenderFarmProtocol.defaultChunkSizeBytes
        ) {
            self.allowInsecureTransports = allowInsecureTransports
            self.discoveryIntervalSeconds = discoveryIntervalSeconds
            self.chunkSizeBytes = chunkSizeBytes
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

    /// Refuses insecure transports unless explicitly allowed.
    public func validate(submission: RenderFarmJobSubmission) throws {
        if submission.transport == .plainHTTP && !configuration.allowInsecureTransports {
            throw RenderFarmError.unsupportedTransport(
                "plainHTTP requires Configuration.allowInsecureTransports = true"
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
