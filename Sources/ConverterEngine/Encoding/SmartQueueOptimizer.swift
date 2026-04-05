// ============================================================================
// MeedyaConverter — SmartQueueOptimizer (Issue #326)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - QueueStrategy

/// Strategy for reordering encoding jobs in the queue to optimise throughput,
/// resource utilisation, or user-defined priority.
///
/// Each strategy sorts the job list differently before execution begins.
/// The default `.fifo` preserves insertion order (first-in, first-out).
public enum QueueStrategy: String, Codable, Sendable, CaseIterable {

    /// Process jobs in the order they were added (first-in, first-out).
    case fifo

    /// Process shortest-duration jobs first to maximise completed-job count
    /// early in the queue. Uses `estimatedSourceDuration` on each job.
    case shortestFirst

    /// Process longest-duration jobs first to front-load heavy work while
    /// the system is freshly started and thermal headroom is greatest.
    case longestFirst

    /// Batch hardware-accelerated (GPU) jobs first so the discrete GPU
    /// stays busy in a contiguous block, reducing context-switch overhead.
    case gpuFirst

    /// Batch CPU-only (software encoder) jobs first — useful when the GPU
    /// is reserved for other workloads (e.g., live preview rendering).
    case cpuFirst

    /// Sort by the job's `priority` field, highest first.
    case priority

    /// Estimate total encode wall-clock time using `FileSizeEstimator`
    /// heuristics and sort ascending so the fastest jobs complete first.
    case estimatedTime

    // MARK: - Display

    /// A human-readable label suitable for picker controls.
    public var displayName: String {
        switch self {
        case .fifo:           return "First In, First Out"
        case .shortestFirst:  return "Shortest First"
        case .longestFirst:   return "Longest First"
        case .gpuFirst:       return "GPU Jobs First"
        case .cpuFirst:       return "CPU Jobs First"
        case .priority:       return "By Priority"
        case .estimatedTime:  return "Estimated Time (fastest first)"
        }
    }
}

// MARK: - SmartQueueOptimizer

/// Reorders an array of `EncodingJobConfig` according to a chosen
/// `QueueStrategy` to improve throughput and user experience.
///
/// All methods are pure functions — the optimiser does not mutate global state
/// and is safe to call from any concurrency domain.
public struct SmartQueueOptimizer: Sendable {

    // MARK: - Public API

    /// Reorder `jobs` according to `strategy`.
    ///
    /// - Parameters:
    ///   - jobs: The current list of encoding job configurations.
    ///   - strategy: The ordering strategy to apply.
    ///   - benchmarkResults: Optional benchmark data used by `.estimatedTime`.
    /// - Returns: A new array with jobs sorted per the chosen strategy.
    public static func optimize(
        jobs: [EncodingJobConfig],
        strategy: QueueStrategy,
        benchmarkResults: [BenchmarkResult]? = nil
    ) -> [EncodingJobConfig] {
        switch strategy {
        case .fifo:
            return jobs

        case .shortestFirst:
            return jobs.sorted { ($0.estimatedSourceDuration ?? .infinity) < ($1.estimatedSourceDuration ?? .infinity) }

        case .longestFirst:
            return jobs.sorted { ($0.estimatedSourceDuration ?? 0) > ($1.estimatedSourceDuration ?? 0) }

        case .gpuFirst:
            return jobs.sorted { lhs, rhs in
                if lhs.profile.useHardwareEncoding != rhs.profile.useHardwareEncoding {
                    return lhs.profile.useHardwareEncoding
                }
                return lhs.createdAt < rhs.createdAt
            }

        case .cpuFirst:
            return jobs.sorted { lhs, rhs in
                if lhs.profile.useHardwareEncoding != rhs.profile.useHardwareEncoding {
                    return !lhs.profile.useHardwareEncoding
                }
                return lhs.createdAt < rhs.createdAt
            }

        case .priority:
            return jobs.sorted { $0.priority > $1.priority }

        case .estimatedTime:
            return jobs.sorted { lhs, rhs in
                let lhsDuration = estimateJobDuration(job: lhs, benchmarkResults: benchmarkResults) ?? .infinity
                let rhsDuration = estimateJobDuration(job: rhs, benchmarkResults: benchmarkResults) ?? .infinity
                return lhsDuration < rhsDuration
            }
        }
    }

    // MARK: - Duration Estimation

    /// Estimate the wall-clock encoding duration for a single job.
    ///
    /// When `benchmarkResults` contains a matching entry (same codec, preset,
    /// and hardware-acceleration flag), the source duration is divided by the
    /// benchmark speed factor. Otherwise a conservative 1x speed is assumed.
    ///
    /// - Parameters:
    ///   - job: The encoding job configuration.
    ///   - benchmarkResults: Optional array of prior benchmark measurements.
    /// - Returns: Estimated wall-clock seconds, or `nil` if the source
    ///   duration is unknown and no heuristic can be applied.
    public static func estimateJobDuration(
        job: EncodingJobConfig,
        benchmarkResults: [BenchmarkResult]?
    ) -> TimeInterval? {
        guard let sourceDuration = job.estimatedSourceDuration, sourceDuration > 0 else {
            return nil
        }

        // Attempt to find a matching benchmark for accurate prediction.
        if let benchmarks = benchmarkResults {
            let codecRaw = job.profile.videoCodec?.rawValue ?? ""
            let preset = job.profile.videoPreset ?? "medium"
            let hwAccel = job.profile.useHardwareEncoding

            // Find the best matching benchmark: codec + preset + hw match.
            // Speed factor is derived from benchmark fps assuming a standard
            // 30 fps source — fps / 30 gives a real-time multiplier.
            let match = benchmarks.first { benchmark in
                benchmark.codec == codecRaw
                    && benchmark.preset == preset
                    && benchmark.hardwareAccelerated == hwAccel
            }

            if let match, match.fps > 0 {
                let speedFactor = match.fps / 30.0
                return sourceDuration / speedFactor
            }

            // Fallback: match codec + hw only.
            let partialMatch = benchmarks.first { benchmark in
                benchmark.codec == codecRaw
                    && benchmark.hardwareAccelerated == hwAccel
            }

            if let partialMatch, partialMatch.fps > 0 {
                let speedFactor = partialMatch.fps / 30.0
                return sourceDuration / speedFactor
            }
        }

        // Fallback heuristic: estimate from file-size estimator output size ratio.
        // Use the source duration divided by a conservative speed factor.
        let conservativeSpeed: Double = job.profile.useHardwareEncoding ? 3.0 : 1.0
        return sourceDuration / conservativeSpeed
    }
}

// MARK: - EncodingJobConfig Extension

extension EncodingJobConfig {

    /// Estimated source media duration in seconds, used by the queue optimiser
    /// for sorting strategies that depend on content length.
    ///
    /// This value is populated externally after probing the source file.
    /// When not set, duration-based strategies treat the job as having
    /// infinite duration (sorted to the end for `.shortestFirst`).
    public var estimatedSourceDuration: TimeInterval? {
        get {
            guard let raw = extraArguments.first(where: { $0.hasPrefix("__duration:") }) else {
                return nil
            }
            return TimeInterval(raw.replacingOccurrences(of: "__duration:", with: ""))
        }
        set {
            // Remove any existing duration tag.
            extraArguments.removeAll { $0.hasPrefix("__duration:") }
            if let value = newValue {
                extraArguments.append("__duration:\(value)")
            }
        }
    }
}
