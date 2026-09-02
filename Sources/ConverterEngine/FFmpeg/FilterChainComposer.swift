// ============================================================================
// MeedyaConverter — FilterChainComposer
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - FilterChainComposer

/// Joins independently-sourced FFmpeg filter-chain fragments (e.g. a crop
/// filter computed from source-frame coordinates and a filter graph staged
/// from `FilterGraphEditorView`) into a single `-vf`/`-af` value, in order.
public enum FilterChainComposer {
    /// Comma-joins non-empty filter fragments in order; nil when nothing remains.
    public static func compose(_ parts: String?...) -> String? {
        let kept = parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept.joined(separator: ",")
    }
}
