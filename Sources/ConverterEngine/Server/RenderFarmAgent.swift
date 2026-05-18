// ============================================================================
// MeedyaConverter — RenderFarmAgent
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Remote render-farm submission primitives. Lets a local MeedyaConverter
// client submit encoding jobs to remote Mac/server agents, monitor progress,
// and download the finished output. The on-device agent binary is a separate
// deliverable and will reuse `EncodingJob`, `EncodingEngine`, and
// `FFmpegProcessController` from this target when it runs on the remote host.
//
// Design goals:
//   - Local-first: agents are discovered via Bonjour on the LAN, with manual
//     host/port entry as a fallback for WAN or offline networks.
//   - Secure-by-default: SSH key-based authentication, password auth refused
//     unless the caller explicitly opts in.
//   - Resumable: chunked source-file transfer with a SHA-256 checksum
//     verifying each chunk and the final assembled file.
//   - Protocol-agnostic progress: job state is delivered via an AsyncStream
//     so UI code can subscribe without pulling in WebSocket or HTTP libs.
//
// This file intentionally contains only pure value types and deterministic
// helper methods so unit tests can exercise the submission protocol without
// standing up a real agent. Transport glue (Bonjour discovery, SSH tunnel
// setup, HTTP/WebSocket transport) is stubbed behind `RenderFarmTransport`
// and replaced with real implementations when the agent app ships.
//
// GitHub Issue #346 — Remote encoding / render farm submission.
// ============================================================================

import Foundation

// MARK: - RenderFarmError

/// Errors raised by the render-farm subsystem.
public enum RenderFarmError: LocalizedError, Sendable {
    case agentNotReachable(String)
    case authenticationFailed(String)
    case transferIntegrityFailed(expected: String, got: String)
    case jobNotFound(UUID)
    case agentReturnedError(code: Int, detail: String)
    case unsupportedTransport(String)

    public var errorDescription: String? {
        switch self {
        case .agentNotReachable(let host):
            return "Render-farm agent at \(host) is not reachable."
        case .authenticationFailed(let detail):
            return "Authentication failed: \(detail)"
        case .transferIntegrityFailed(let expected, let got):
            return "Source file integrity check failed. Expected SHA-256 \(expected), got \(got)."
        case .jobNotFound(let id):
            return "Job \(id.uuidString) not found on agent."
        case .agentReturnedError(let code, let detail):
            return "Agent returned error \(code): \(detail)"
        case .unsupportedTransport(let name):
            return "Unsupported render-farm transport: \(name)."
        }
    }
}

// MARK: - RenderFarmAgentInfo

/// Describes a discovered or manually-configured render-farm agent.
public struct RenderFarmAgentInfo: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Display name. Defaults to the hostname for discovered agents.
    public var displayName: String
    /// IPv4/IPv6 address or hostname.
    public var host: String
    /// TCP port the agent is listening on (default 2229).
    public var port: Int
    /// SSH username used when transport is `.ssh`.
    public var sshUsername: String?
    /// True if Bonjour-discovered, false if manually added.
    public var discovered: Bool
    /// Reported CPU architecture (e.g. "arm64", "x86_64").
    public var architecture: String?
    /// Reported GPU/hardware encoder families (e.g. ["videotoolbox", "nvenc"]).
    public var hardwareEncoders: [String]

    public init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        port: Int = 2229,
        sshUsername: String? = nil,
        discovered: Bool = false,
        architecture: String? = nil,
        hardwareEncoders: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.sshUsername = sshUsername
        self.discovered = discovered
        self.architecture = architecture
        self.hardwareEncoders = hardwareEncoders
    }

    /// Canonical `host:port` string for logging and manual config UI.
    public var endpoint: String { "\(host):\(port)" }
}

// MARK: - RenderFarmTransport

/// Transport mechanism the client uses to talk to an agent.
public enum RenderFarmTransport: String, Codable, Sendable, CaseIterable {
    /// SSH tunnel + HTTP over loopback. Recommended for WAN and untrusted
    /// networks.
    case ssh
    /// Direct TLS over the Bonjour-discovered port. Suitable for trusted
    /// LAN use only — the agent binds a self-signed certificate that the
    /// client pins by SHA-256 fingerprint on first connect.
    case tls
    /// Plain HTTP + shared secret. Insecure; only available when the
    /// client's `RenderFarmClient.Configuration` carries an
    /// `InsecureTransportOverride` token. See issue #380 for the audit
    /// follow-up that introduced the token.
    case plainHTTP
}

// MARK: - RenderFarmJobState

/// Lifecycle of a submitted render-farm job.
public enum RenderFarmJobState: String, Codable, Sendable, CaseIterable {
    case queued
    case transferring
    case encoding
    case finalising
    case completed
    case failed
    case cancelled
}

// MARK: - RenderFarmJobStatus

/// Snapshot of a job's state on the agent.
public struct RenderFarmJobStatus: Codable, Sendable, Hashable {
    public let jobId: UUID
    public var state: RenderFarmJobState
    /// Progress percentage 0.0 – 1.0.
    public var progress: Double
    /// Current FFS frame (if reported).
    public var currentFrame: UInt64?
    /// Total frames (if known).
    public var totalFrames: UInt64?
    /// Encoding speed multiplier (e.g. "1.5x realtime" → 1.5).
    public var speedMultiplier: Double?
    /// Human-readable status message.
    public var message: String?

    public init(
        jobId: UUID,
        state: RenderFarmJobState,
        progress: Double,
        currentFrame: UInt64? = nil,
        totalFrames: UInt64? = nil,
        speedMultiplier: Double? = nil,
        message: String? = nil
    ) {
        self.jobId = jobId
        self.state = state
        self.progress = progress
        self.currentFrame = currentFrame
        self.totalFrames = totalFrames
        self.speedMultiplier = speedMultiplier
        self.message = message
    }
}

// MARK: - RenderFarmJobSubmission

/// All information needed to submit a job to a remote agent.
public struct RenderFarmJobSubmission: Codable, Sendable {
    public let jobId: UUID
    public let agentId: UUID
    /// Profile name or inline YAML the agent should use.
    public let profileIdentifier: String
    /// Original filename (agent uses this for the output's basename).
    public let sourceFilename: String
    /// SHA-256 hex string of the full source payload — used by the agent
    /// to verify the assembled transfer and reject tampered chunks.
    public let sourceSHA256: String
    /// Size in bytes.
    public let sourceSizeBytes: UInt64
    /// Transport mechanism.
    public let transport: RenderFarmTransport
    /// ISO8601 submission timestamp.
    public let submittedAt: String

    public init(
        jobId: UUID = UUID(),
        agentId: UUID,
        profileIdentifier: String,
        sourceFilename: String,
        sourceSHA256: String,
        sourceSizeBytes: UInt64,
        transport: RenderFarmTransport = .ssh,
        submittedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.jobId = jobId
        self.agentId = agentId
        self.profileIdentifier = profileIdentifier
        self.sourceFilename = sourceFilename
        self.sourceSHA256 = sourceSHA256
        self.sourceSizeBytes = sourceSizeBytes
        self.transport = transport
        self.submittedAt = submittedAt
    }
}

// MARK: - RenderFarmChunk

/// A single chunk of a chunked source file upload. Agents verify each chunk's
/// SHA-256 before appending it to the assembled source payload, and reject
/// the entire transfer if any chunk fails to verify.
public struct RenderFarmChunk: Sendable, Hashable {
    public let jobId: UUID
    public let index: UInt32
    public let offset: UInt64
    public let payload: Data
    public let sha256: String

    public init(jobId: UUID, index: UInt32, offset: UInt64, payload: Data, sha256: String) {
        self.jobId = jobId
        self.index = index
        self.offset = offset
        self.payload = payload
        self.sha256 = sha256
    }
}

// MARK: - RenderFarmProtocol

/// Pure helpers exercising the submission protocol. Split out so unit tests
/// can drive the logic without a running agent.
public enum RenderFarmProtocol: Sendable {

    /// Recommended chunk size in bytes (4 MiB). Balances HTTP overhead with
    /// resumable-retry granularity.
    public static let defaultChunkSizeBytes: UInt64 = 4 * 1024 * 1024

    /// Default TCP port for agents. Picked to avoid collisions with common
    /// media services (AirPlay: 5000, Plex: 32400).
    public static let defaultAgentPort: Int = 2229

    /// Bonjour service type used for discovery.
    public static let bonjourServiceType = "_meedyaconverter-agent._tcp"

    /// Compute the number of chunks a source of the given size will split
    /// into when using the default chunk size.
    public static func chunkCount(forSourceSizeBytes size: UInt64) -> UInt32 {
        chunkCount(forSourceSizeBytes: size, chunkSizeBytes: defaultChunkSizeBytes)
    }

    public static func chunkCount(
        forSourceSizeBytes size: UInt64,
        chunkSizeBytes: UInt64
    ) -> UInt32 {
        guard chunkSizeBytes > 0 else { return 0 }
        let full = size / chunkSizeBytes
        let remainder = size % chunkSizeBytes == 0 ? UInt64(0) : UInt64(1)
        return UInt32(full + remainder)
    }

    /// Checksum validation for an assembled upload. Returns an error if
    /// the observed SHA-256 differs from what the client advertised.
    public static func validateAssembledChecksum(
        expected: String,
        observed: String
    ) throws {
        let lhs = expected.lowercased()
        let rhs = observed.lowercased()
        guard lhs == rhs else {
            throw RenderFarmError.transferIntegrityFailed(expected: lhs, got: rhs)
        }
    }

    /// Build the REST path a client uses to submit a new job to an agent.
    /// Using a versioned prefix lets the agent evolve without breaking
    /// older clients.
    public static func submitPath(jobId: UUID) -> String {
        "/v1/jobs/\(jobId.uuidString.lowercased())"
    }

    /// Path for uploading a single chunk.
    public static func chunkPath(jobId: UUID, index: UInt32) -> String {
        "/v1/jobs/\(jobId.uuidString.lowercased())/chunks/\(index)"
    }

    /// Path for requesting a status snapshot.
    public static func statusPath(jobId: UUID) -> String {
        "/v1/jobs/\(jobId.uuidString.lowercased())/status"
    }

    /// Path for downloading the completed output file.
    public static func downloadPath(jobId: UUID) -> String {
        "/v1/jobs/\(jobId.uuidString.lowercased())/output"
    }

    /// Path for cancelling an in-flight job.
    public static func cancelPath(jobId: UUID) -> String {
        "/v1/jobs/\(jobId.uuidString.lowercased())/cancel"
    }
}
