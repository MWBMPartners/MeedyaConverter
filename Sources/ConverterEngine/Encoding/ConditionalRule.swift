// ============================================================================
// MeedyaConverter — ConditionalRule
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Defines the conditional encoding rules system. Rules allow automatic
// profile selection based on source file properties such as resolution,
// codec, HDR status, duration, file size, extension, and channel count.
//
// Each rule contains one or more conditions (AND logic) and references
// an encoding profile by UUID. The `RuleEngine` evaluates rules in
// priority order and returns the first fully-matching profile.
//
// Phase 11 — Conditional Encoding Rules (Issue #276)
// ---------------------------------------------------------------------------

import Foundation

// MARK: - ComparisonOp

/// Comparison operators for numeric and dimensional rule conditions.
public enum ComparisonOp: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Exactly equal.
    case equal = "equal"

    /// Not equal.
    case notEqual = "notEqual"

    /// Strictly greater than.
    case greaterThan = "greaterThan"

    /// Strictly less than.
    case lessThan = "lessThan"

    /// Greater than or equal to.
    case greaterOrEqual = "greaterOrEqual"

    /// Less than or equal to.
    case lessOrEqual = "lessOrEqual"

    /// A stable identifier for `Identifiable` conformance.
    public var id: String { rawValue }

    /// Human-readable display label for UI dropdowns.
    public var displayName: String {
        switch self {
        case .equal: return "="
        case .notEqual: return "!="
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .greaterOrEqual: return ">="
        case .lessOrEqual: return "<="
        }
    }
}

// MARK: - RuleCondition

/// A single condition within a conditional encoding rule.
///
/// Conditions are evaluated against a `MediaFile`'s properties. Multiple
/// conditions within the same rule are combined with AND logic — all must
/// match for the rule to fire.
public enum RuleCondition: Codable, Sendable, Identifiable {
    /// Match source resolution against width x height.
    ///
    /// Comparison is performed on the total pixel count (width * height)
    /// to handle non-standard aspect ratios correctly.
    case resolution(op: ComparisonOp, width: Int, height: Int)

    /// Match source video codec.
    case codec(is: VideoCodec)

    /// Match whether the source has HDR content.
    case hasHDR(Bool)

    /// Match source duration in seconds.
    case duration(op: ComparisonOp, seconds: TimeInterval)

    /// Match source file size in bytes.
    case fileSize(op: ComparisonOp, bytes: Int64)

    /// Match source file extension (case-insensitive, without leading dot).
    case `extension`(String)

    /// Match audio channel count of the primary audio stream.
    case channelCount(op: ComparisonOp, count: Int)

    /// A stable identifier derived from the condition's content.
    public var id: String {
        switch self {
        case .resolution(let op, let w, let h):
            return "resolution-\(op.rawValue)-\(w)x\(h)"
        case .codec(let codec):
            return "codec-\(codec.rawValue)"
        case .hasHDR(let value):
            return "hasHDR-\(value)"
        case .duration(let op, let seconds):
            return "duration-\(op.rawValue)-\(seconds)"
        case .fileSize(let op, let bytes):
            return "fileSize-\(op.rawValue)-\(bytes)"
        case .extension(let ext):
            return "extension-\(ext)"
        case .channelCount(let op, let count):
            return "channelCount-\(op.rawValue)-\(count)"
        }
    }

    /// Human-readable description for display in the rule editor UI.
    public var displayDescription: String {
        switch self {
        case .resolution(let op, let w, let h):
            return "Resolution \(op.displayName) \(w)x\(h)"
        case .codec(let codec):
            return "Codec is \(codec.displayName)"
        case .hasHDR(let value):
            return value ? "Has HDR" : "No HDR"
        case .duration(let op, let seconds):
            let formatted = formatDuration(seconds)
            return "Duration \(op.displayName) \(formatted)"
        case .fileSize(let op, let bytes):
            let formatted = ByteCountFormatter.string(
                fromByteCount: bytes, countStyle: .file
            )
            return "File size \(op.displayName) \(formatted)"
        case .extension(let ext):
            return "Extension is .\(ext)"
        case .channelCount(let op, let count):
            return "Audio channels \(op.displayName) \(count)"
        }
    }

    /// Formats a duration in seconds as "HH:MM:SS" or "MM:SS".
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - ConditionalRule

/// A named, prioritised encoding rule that maps a set of conditions
/// to an encoding profile.
///
/// When the rule engine evaluates a source file, it checks each rule
/// in ascending priority order. The first rule whose conditions all
/// match determines the encoding profile to use.
///
/// - `conditions` use AND logic: every condition must match.
/// - `priority` determines evaluation order (lower = evaluated first).
/// - `isEnabled` allows toggling rules without deletion.
///
/// Phase 11 — Conditional Encoding Rules (Issue #276)
public struct ConditionalRule: Identifiable, Codable, Sendable {

    /// Unique identifier for this rule.
    public let id: UUID

    /// Human-readable name (e.g. "4K HDR to H.265 HQ").
    public var name: String

    /// The conditions that must all match (AND logic) for this rule to fire.
    public var conditions: [RuleCondition]

    /// The UUID of the encoding profile to apply when this rule matches.
    public var profileId: UUID

    /// Whether this rule is active. Disabled rules are skipped during evaluation.
    public var isEnabled: Bool

    /// Evaluation priority. Lower values are evaluated first.
    public var priority: Int

    // MARK: - Initialiser

    public init(
        id: UUID = UUID(),
        name: String,
        conditions: [RuleCondition] = [],
        profileId: UUID,
        isEnabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.conditions = conditions
        self.profileId = profileId
        self.isEnabled = isEnabled
        self.priority = priority
    }
}

// MARK: - RuleEngine

/// Evaluates conditional encoding rules against a source `MediaFile`.
///
/// The engine processes rules sorted by ascending priority. The first
/// rule whose conditions all evaluate to `true` wins, and its linked
/// encoding profile is returned.
///
/// Thread-safe: all methods are pure functions with no shared mutable state.
public struct RuleEngine: Sendable {

    // MARK: - Rule Evaluation

    /// Evaluates all enabled rules against a source file and returns
    /// the encoding profile of the first matching rule.
    ///
    /// - Parameters:
    ///   - rules: The conditional rules to evaluate, in any order
    ///     (they will be sorted by priority internally).
    ///   - file: The source media file to match against.
    ///   - profileStore: The profile store to look up the matched profile.
    /// - Returns: The `EncodingProfile` for the first matching rule,
    ///   or `nil` if no rule matches.
    public static func evaluateRules(
        _ rules: [ConditionalRule],
        for file: MediaFile,
        profileStore: EncodingProfileStore
    ) -> EncodingProfile? {
        let sortedRules = rules
            .filter(\.isEnabled)
            .sorted { $0.priority < $1.priority }

        for rule in sortedRules {
            let allMatch = rule.conditions.allSatisfy { condition in
                evaluateCondition(condition, for: file)
            }
            if allMatch {
                return profileStore.profile(id: rule.profileId)
            }
        }
        return nil
    }

    /// Evaluates a single condition against a source file.
    ///
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - file: The source media file.
    /// - Returns: `true` if the condition matches the file's properties.
    public static func evaluateCondition(
        _ condition: RuleCondition,
        for file: MediaFile
    ) -> Bool {
        switch condition {
        case .resolution(let op, let targetW, let targetH):
            return evaluateResolution(op: op, targetWidth: targetW, targetHeight: targetH, file: file)

        case .codec(let targetCodec):
            return file.primaryVideoStream?.videoCodec == targetCodec

        case .hasHDR(let expected):
            return file.hasHDR == expected

        case .duration(let op, let targetSeconds):
            guard let fileDuration = file.duration else { return false }
            return compare(fileDuration, op, targetSeconds)

        case .fileSize(let op, let targetBytes):
            guard let size = file.fileSize else { return false }
            return compare(Int64(size), op, targetBytes)

        case .extension(let targetExt):
            let fileExt = file.fileURL.pathExtension.lowercased()
            return fileExt == targetExt.lowercased()

        case .channelCount(let op, let targetCount):
            guard let layout = file.primaryAudioStream?.channelLayout else {
                return false
            }
            return compare(layout.channelCount, op, targetCount)
        }
    }

    // MARK: - Private Helpers

    /// Evaluates a resolution condition using total pixel count comparison.
    private static func evaluateResolution(
        op: ComparisonOp,
        targetWidth: Int,
        targetHeight: Int,
        file: MediaFile
    ) -> Bool {
        guard let video = file.primaryVideoStream,
              let sourceW = video.width,
              let sourceH = video.height else {
            return false
        }
        let sourcePixels = sourceW * sourceH
        let targetPixels = targetWidth * targetHeight
        return compare(sourcePixels, op, targetPixels)
    }

    /// Generic comparison using `ComparisonOp` on `Comparable` values.
    private static func compare<T: Comparable>(
        _ lhs: T,
        _ op: ComparisonOp,
        _ rhs: T
    ) -> Bool {
        switch op {
        case .equal: return lhs == rhs
        case .notEqual: return lhs != rhs
        case .greaterThan: return lhs > rhs
        case .lessThan: return lhs < rhs
        case .greaterOrEqual: return lhs >= rhs
        case .lessOrEqual: return lhs <= rhs
        }
    }
}
