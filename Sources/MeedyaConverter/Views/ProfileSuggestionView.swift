// ============================================================================
// MeedyaConverter — ProfileSuggestionView (Issue #271)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - ProfileSuggestionView

/// Compact view displaying the top profile suggestions for the current source file.
///
/// Shows up to 3 suggestion cards, each with the profile name, a confidence
/// badge, a reason explanation, and a "Use This Profile" button. Designed to
/// be embedded as a banner at the top of the output settings area or presented
/// as a popover when a file is first imported.
///
/// Phase 7 / Issue #271
struct ProfileSuggestionView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - Properties

    /// The source media file to analyse for suggestions.
    let sourceFile: MediaFile

    /// All available encoding profiles to choose from.
    let profiles: [EncodingProfile]

    /// Callback when the user selects a suggested profile.
    let onSelectProfile: (EncodingProfile) -> Void

    // MARK: - State

    /// The computed suggestions for the current source file.
    @State private var suggestions: [ProfileSuggestion] = []

    /// Whether the suggestions have been computed.
    @State private var hasComputed: Bool = false

    /// Index of the suggestion whose "Why?" explanation is expanded.
    @State private var expandedIndex: Int?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("Suggested Profiles")
                    .font(.headline)

                Spacer()

                if !suggestions.isEmpty {
                    Text("Based on source analysis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !hasComputed {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analysing source...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if suggestions.isEmpty {
                Text("No strong profile recommendations for this source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Suggestion cards — show top 3.
                ForEach(Array(suggestions.prefix(3).enumerated()), id: \.element.id) { index, suggestion in
                    suggestionCard(suggestion, index: index)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            computeSuggestions()
        }
    }

    // MARK: - Suggestion Card

    /// A single suggestion card with profile name, confidence, reason, and action button.
    private func suggestionCard(_ suggestion: ProfileSuggestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                // Profile name and category.
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.profile.name)
                        .font(.subheadline.bold())

                    Text(suggestion.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColour(suggestion.category).opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                // Confidence badge.
                confidenceBadge(suggestion.confidence)

                // Use This Profile button.
                Button("Use This Profile") {
                    onSelectProfile(suggestion.profile)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Reason text (always visible as a brief summary).
            Text(briefReason(suggestion.reason))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(expandedIndex == index ? nil : 2)

            // "Why?" toggle for expanded explanation.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedIndex = expandedIndex == index ? nil : index
                }
            } label: {
                HStack(spacing: 2) {
                    Text(expandedIndex == index ? "Less" : "Why?")
                        .font(.caption2)
                    Image(systemName: expandedIndex == index ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            if expandedIndex == index {
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if index < min(suggestions.count, 3) - 1 {
                Divider()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Confidence Badge

    /// Visual badge showing the confidence level (0–100%).
    private func confidenceBadge(_ confidence: Double) -> some View {
        let percentage = Int(confidence * 100)
        let colour = confidenceColour(confidence)

        return HStack(spacing: 4) {
            Circle()
                .fill(colour)
                .frame(width: 8, height: 8)
            Text("\(percentage)%")
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(colour)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(colour.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    /// Compute profile suggestions from the source file.
    private func computeSuggestions() {
        guard !hasComputed else { return }
        suggestions = ProfileSuggester.suggest(for: sourceFile, profiles: profiles)
        hasComputed = true
    }

    /// Colour for the confidence indicator.
    private func confidenceColour(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .orange
        default: return .yellow
        }
    }

    /// Colour for category badges.
    private func categoryColour(_ category: String) -> Color {
        switch category {
        case "Best Quality": return .purple
        case "Best Match": return .blue
        case "Smallest Size": return .green
        case "Fastest": return .orange
        default: return .gray
        }
    }

    /// Extract a brief first-sentence summary from the full reason string.
    private func briefReason(_ reason: String) -> String {
        guard let firstPeriod = reason.firstIndex(of: ".") else {
            return reason
        }
        return String(reason[reason.startIndex...firstPeriod])
    }
}
