// ============================================================================
// MeedyaConverter — ParallelEncoder (Issue #286)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - ParallelEncoderConfig
// ---------------------------------------------------------------------------
/// Configuration for parallel (concurrent) encoding sessions.
///
/// Controls the maximum number of simultaneous encoding jobs, CPU affinity
/// pinning, and GPU sharing behaviour. Persisted alongside user preferences
/// so that the optimal concurrency level is remembered across launches.
///
/// Phase 8 — Split View / Parallel Encoding (Issue #286)
public struct ParallelEncoderConfig: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Maximum number of encoding jobs that may run simultaneously.
    ///
    /// A value of `1` disables parallelism (sequential mode).
    /// Values above `ProcessInfo.processInfo.activeProcessorCount` are
    /// clamped at runtime to prevent CPU over-subscription.
    public var maxConcurrent: Int

    /// When `true`, each encoding process is pinned to a specific CPU
    /// core range using `taskpolicy` (macOS) to reduce context-switch
    /// overhead and improve cache locality.
    public var cpuAffinity: Bool

    /// When `true`, multiple GPU-accelerated encodes (e.g., VideoToolbox)
    /// are allowed to share the GPU simultaneously. Disabling this
    /// serialises GPU encodes while still parallelising CPU-based jobs.
    public var gpuSharing: Bool

    /// The scheduling priority for encoding processes.
    /// Range: 0.0 (background) to 1.0 (real-time). Default 0.5.
    public var priority: Double

    // MARK: - Initialisation

    /// Creates a new parallel encoder configuration.
    ///
    /// - Parameters:
    ///   - maxConcurrent: Maximum simultaneous jobs. Defaults to system-recommended.
    ///   - cpuAffinity: Whether to pin processes to cores. Defaults to `false`.
    ///   - gpuSharing: Whether to allow concurrent GPU encodes. Defaults to `true`.
    ///   - priority: Scheduling priority (0.0–1.0). Defaults to `0.5`.
    public init(
        maxConcurrent: Int = ParallelEncoder.determineMaxConcurrent(),
        cpuAffinity: Bool = false,
        gpuSharing: Bool = true,
        priority: Double = 0.5
    ) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.cpuAffinity = cpuAffinity
        self.gpuSharing = gpuSharing
        self.priority = min(1.0, max(0.0, priority))
    }
}

// ---------------------------------------------------------------------------
// MARK: - ResourceEstimate
// ---------------------------------------------------------------------------
/// Estimated system resource requirements for a single encoding job.
///
/// Used by the parallel scheduler to determine how many jobs can run
/// concurrently without exceeding available CPU, GPU, or RAM capacity.
public struct ResourceEstimate: Sendable, Equatable {

    /// Relative CPU weight (0.0–1.0). A 1080p software encode might
    /// weight 0.5; a 4K HEVC encode might weight 1.0.
    public let cpuWeight: Double

    /// Relative GPU weight (0.0–1.0). Zero for CPU-only codecs;
    /// close to 1.0 for VideoToolbox-accelerated encodes.
    public let gpuWeight: Double

    /// Estimated RAM usage in megabytes for this encode.
    public let ramMB: Int

    public init(cpuWeight: Double, gpuWeight: Double, ramMB: Int) {
        self.cpuWeight = cpuWeight
        self.gpuWeight = gpuWeight
        self.ramMB = ramMB
    }
}

// ---------------------------------------------------------------------------
// MARK: - ParallelEncoder
// ---------------------------------------------------------------------------
/// Utilities for determining optimal parallelism and partitioning encoding
/// jobs across available hardware resources.
///
/// `ParallelEncoder` is a value-type namespace (struct with static methods)
/// that does not hold any mutable state. All decisions are pure functions
/// of the inputs and current hardware capabilities.
///
/// ## Resource Model
///
/// Each encoding job is assigned a `ResourceEstimate` based on its codec,
/// resolution, and whether hardware acceleration is requested. The
/// scheduler then groups and sequences jobs so that the aggregate resource
/// demand at any point in time stays within safe limits.
///
/// Phase 8 — Split View / Parallel Encoding (Issue #286)
public struct ParallelEncoder: Sendable {

    // MARK: - System Introspection

    /// Determines the recommended maximum number of concurrent encoding
    /// jobs based on the current system's CPU core count and available RAM.
    ///
    /// ## Heuristic
    ///
    /// - Base concurrency = `activeProcessorCount / 2` (each encode
    ///   typically saturates ~2 cores for H.264, ~4 for HEVC).
    /// - RAM constraint: at least 2 GB per concurrent job.
    /// - Minimum: always returns at least 1.
    /// - Maximum: capped at 8 to avoid diminishing returns from
    ///   context-switch overhead.
    ///
    /// - Returns: Recommended number of concurrent encoding jobs.
    public static func determineMaxConcurrent() -> Int {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let physicalMemoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

        // Each encode typically uses ~2 cores effectively
        let cpuBasedLimit = max(1, coreCount / 2)

        // Reserve 2 GB per concurrent encode + 4 GB for the system
        let ramBasedLimit = max(1, (physicalMemoryGB - 4) / 2)

        // Take the minimum of CPU and RAM constraints, cap at 8
        let recommended = min(cpuBasedLimit, ramBasedLimit, 8)

        return max(1, recommended)
    }

    // MARK: - Job Partitioning

    /// Partitions encoding jobs into batches that can run concurrently
    /// without exceeding resource limits.
    ///
    /// Jobs are categorised by their primary resource type (GPU vs CPU)
    /// and grouped so that GPU-bound jobs are parallelised with CPU-bound
    /// jobs where possible, maximising total throughput.
    ///
    /// - Parameters:
    ///   - jobs: All encoding jobs to partition.
    ///   - maxConcurrent: Maximum simultaneous jobs allowed.
    /// - Returns: An array of job batches. Each inner array contains jobs
    ///   that should run concurrently; batches are executed sequentially.
    public static func partitionJobs(
        jobs: [EncodingJobConfig],
        maxConcurrent: Int
    ) -> [[EncodingJobConfig]] {
        guard !jobs.isEmpty else { return [] }

        let effectiveMax = max(1, maxConcurrent)

        // Separate jobs by primary resource type
        var gpuJobs: [EncodingJobConfig] = []
        var cpuJobs: [EncodingJobConfig] = []

        for job in jobs {
            let estimate = estimateResourceUsage(job: job)
            if estimate.gpuWeight > 0.3 {
                gpuJobs.append(job)
            } else {
                cpuJobs.append(job)
            }
        }

        // Interleave GPU and CPU jobs in batches to balance resource usage
        var batches: [[EncodingJobConfig]] = []
        var currentBatch: [EncodingJobConfig] = []
        var gpuIndex = 0
        var cpuIndex = 0

        while gpuIndex < gpuJobs.count || cpuIndex < cpuJobs.count {
            // Add one GPU job per batch if available
            if gpuIndex < gpuJobs.count {
                currentBatch.append(gpuJobs[gpuIndex])
                gpuIndex += 1
            }

            // Fill remaining slots with CPU jobs
            while currentBatch.count < effectiveMax && cpuIndex < cpuJobs.count {
                currentBatch.append(cpuJobs[cpuIndex])
                cpuIndex += 1
            }

            if currentBatch.count >= effectiveMax || (gpuIndex >= gpuJobs.count && cpuIndex >= cpuJobs.count) {
                batches.append(currentBatch)
                currentBatch = []
            }
        }

        // Flush any remaining jobs
        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    // MARK: - Resource Estimation

    /// Estimates the CPU, GPU, and RAM requirements for a single encoding job.
    ///
    /// The estimate is based on the job's codec, resolution (inferred from
    /// profile settings), and whether hardware acceleration is enabled.
    ///
    /// - Parameter job: The encoding job configuration to analyse.
    /// - Returns: A `ResourceEstimate` with normalised weights and RAM in MB.
    public static func estimateResourceUsage(job: EncodingJobConfig) -> ResourceEstimate {
        let codec = job.profile.videoCodec

        // Base CPU weight by codec complexity
        var cpuWeight: Double
        var gpuWeight: Double = 0.0
        var ramMB: Int

        switch codec {
        case .h264:
            cpuWeight = 0.4
            ramMB = 512
        case .h265:
            cpuWeight = 0.8
            ramMB = 1024
        case .av1:
            cpuWeight = 0.9
            ramMB = 1536
        case .prores:
            cpuWeight = 0.3
            ramMB = 768
        case .vp9:
            cpuWeight = 0.7
            ramMB = 1024
        default:
            // For hardware-accelerated codecs, favour GPU weight
            if job.profile.useHardwareEncoding {
                cpuWeight = 0.1
                gpuWeight = 0.7
                ramMB = 256
            } else {
                cpuWeight = 0.5
                ramMB = 512
            }
        }

        // Scale by resolution (use outputWidth as proxy)
        let resolutionScale: Double
        let width = job.profile.outputWidth ?? 1920
        switch width {
        case ..<1280:
            resolutionScale = 0.5
        case 1280..<1920:
            resolutionScale = 0.75
        case 1920..<3840:
            resolutionScale = 1.0
        default:
            resolutionScale = 1.5
        }

        cpuWeight = min(1.0, cpuWeight * resolutionScale)
        gpuWeight = min(1.0, gpuWeight * resolutionScale)
        ramMB = Int(Double(ramMB) * resolutionScale)

        return ResourceEstimate(
            cpuWeight: cpuWeight,
            gpuWeight: gpuWeight,
            ramMB: ramMB
        )
    }

    // MARK: - Capacity Check

    /// Checks whether the system has sufficient resources to run
    /// the specified number of concurrent jobs.
    ///
    /// - Parameter concurrentCount: Number of simultaneous jobs to check.
    /// - Returns: `true` if the system can safely run that many jobs.
    public static func canRunConcurrently(count concurrentCount: Int) -> Bool {
        let maxRecommended = determineMaxConcurrent()
        return concurrentCount <= maxRecommended
    }

    /// Returns a human-readable summary of system encoding capacity.
    ///
    /// Example: "8 cores / 32 GB RAM — recommended: 3 concurrent jobs"
    public static var capacitySummary: String {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let recommended = determineMaxConcurrent()
        return "\(cores) cores / \(ramGB) GB RAM — recommended: \(recommended) concurrent jobs"
    }
}
