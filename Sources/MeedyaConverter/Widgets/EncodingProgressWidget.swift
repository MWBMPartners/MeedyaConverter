// ============================================================================
// MeedyaConverter — EncodingProgressWidget (Lock Screen / Desktop Widget)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Defines a WidgetKit widget that displays encoding progress on the macOS
// desktop and (on supported systems) the lock screen.
//
// IMPORTANT: For this widget to actually appear on the lock screen or desktop,
// it must be placed in a separate WidgetKit extension target. WidgetKit
// extensions run as independent processes and cannot directly access the
// host app's in-memory state. Data sharing between the app and the widget
// extension is done via:
//
//   1. An App Group container (e.g. "group.ltd.MWBMpartners.MeedyaConverter")
//      for sharing UserDefaults and files.
//   2. A shared JSON file written by the app with current encoding state,
//      read by the widget's TimelineProvider.
//
// This file contains the complete widget definition that can be moved to
// a WidgetKit extension target when one is added to the project. For now
// it compiles within the main app target as a reference implementation.
//
// Widget families supported:
//   - .systemSmall  — Circular progress ring with percentage
//   - .systemMedium — Progress ring + file name + speed + ETA
//
// Phase 11 / Issue #360
// ---------------------------------------------------------------------------

import SwiftUI
import WidgetKit

// MARK: - App Group Constants

/// Constants for sharing data between the main app and the widget extension.
///
/// The app writes encoding state to a JSON file in the shared App Group
/// container. The widget reads this file in its TimelineProvider to
/// generate timeline entries.
private enum WidgetConstants {

    /// The App Group identifier shared between the main app and widget.
    ///
    /// Must be registered in the Apple Developer portal and added to
    /// both the app and widget extension entitlements.
    static let appGroupIdentifier = "group.ltd.MWBMpartners.MeedyaConverter"

    /// The filename for the shared encoding state JSON file.
    static let stateFileName = "widget_encoding_state.json"

    /// The widget kind identifier used by WidgetKit.
    static let widgetKind = "EncodingProgress"
}

// MARK: - SharedEncodingState

/// The encoding state shared between the main app and the widget extension.
///
/// The main app serialises this struct to a JSON file in the App Group
/// container whenever encoding state changes. The widget's TimelineProvider
/// reads and deserialises it to create timeline entries.
struct SharedEncodingState: Codable, Sendable {

    /// Whether encoding is currently in progress.
    let isEncoding: Bool

    /// Progress as a fraction from 0.0 to 1.0.
    let progress: Double

    /// The name of the file being encoded (without path).
    let fileName: String?

    /// Current encoding speed multiplier (e.g. 2.5 for 2.5x realtime).
    let speed: Double?

    /// Estimated time remaining in seconds.
    let eta: TimeInterval?

    /// Number of jobs in the queue (including current).
    let queueCount: Int

    /// Timestamp when this state was last updated.
    let lastUpdated: Date

    /// Creates a default idle state.
    static let idle = SharedEncodingState(
        isEncoding: false,
        progress: 0.0,
        fileName: nil,
        speed: nil,
        eta: nil,
        queueCount: 0,
        lastUpdated: Date()
    )

    // MARK: - File I/O

    /// Write this state to the shared App Group container.
    ///
    /// Called by the main app whenever encoding state changes.
    /// The widget's TimelineProvider reads this file to generate entries.
    func writeToSharedContainer() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetConstants.appGroupIdentifier
        ) else {
            return
        }

        let fileURL = containerURL.appendingPathComponent(WidgetConstants.stateFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Read the current state from the shared App Group container.
    ///
    /// Called by the widget's TimelineProvider to read the latest state
    /// written by the main app.
    ///
    /// - Returns: The decoded state, or `.idle` if the file doesn't exist
    ///   or cannot be read.
    static func readFromSharedContainer() -> SharedEncodingState {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetConstants.appGroupIdentifier
        ) else {
            return .idle
        }

        let fileURL = containerURL.appendingPathComponent(WidgetConstants.stateFileName)

        guard let data = try? Data(contentsOf: fileURL) else {
            return .idle
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return (try? decoder.decode(SharedEncodingState.self, from: data)) ?? .idle
    }
}

// MARK: - EncodingProgressEntry

/// A single timeline entry for the encoding progress widget.
///
/// WidgetKit uses entries to render the widget at specific points in time.
/// Each entry contains a snapshot of the encoding state that the widget
/// view uses for rendering.
struct EncodingProgressEntry: TimelineEntry {

    /// The date for which this entry is relevant.
    ///
    /// WidgetKit uses this to determine when to display the entry and
    /// when to request the next timeline.
    let date: Date

    /// Whether encoding is currently in progress.
    let isEncoding: Bool

    /// Encoding progress as a fraction from 0.0 to 1.0.
    let progress: Double

    /// The name of the file being encoded (without path), or nil if idle.
    let fileName: String?

    /// Current encoding speed multiplier, or nil if not available.
    let speed: Double?

    /// Estimated time remaining in seconds, or nil if not available.
    let eta: TimeInterval?

    /// A placeholder entry used for widget gallery previews.
    static let placeholder = EncodingProgressEntry(
        date: Date(),
        isEncoding: true,
        progress: 0.65,
        fileName: "Interview_Final_Cut.mov",
        speed: 2.3,
        eta: 245
    )

    /// An idle entry used when no encoding is active.
    static let idle = EncodingProgressEntry(
        date: Date(),
        isEncoding: false,
        progress: 0.0,
        fileName: nil,
        speed: nil,
        eta: nil
    )
}

// MARK: - EncodingProgressProvider

/// Provides timeline entries for the encoding progress widget.
///
/// This provider reads the shared encoding state from the App Group
/// container and generates appropriate timeline entries. When encoding
/// is active, it requests frequent updates (every 30 seconds) to keep
/// the progress display current. When idle, it uses a longer refresh
/// interval (every 15 minutes).
struct EncodingProgressProvider: TimelineProvider {

    /// Provide a placeholder entry for the widget gallery.
    ///
    /// This is shown in the widget picker before the user adds the widget.
    /// It should represent a typical "in use" appearance.
    func placeholder(in context: Context) -> EncodingProgressEntry {
        .placeholder
    }

    /// Provide a snapshot entry for quick display.
    ///
    /// Called when the system needs a single entry immediately (e.g. when
    /// the widget is first added or when the system needs a quick preview).
    ///
    /// - Parameters:
    ///   - context: The widget context including family and display size.
    ///   - completion: Callback to deliver the snapshot entry.
    func getSnapshot(in context: Context, completion: @escaping (EncodingProgressEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        let state = SharedEncodingState.readFromSharedContainer()
        let entry = EncodingProgressEntry(
            date: Date(),
            isEncoding: state.isEncoding,
            progress: state.progress,
            fileName: state.fileName,
            speed: state.speed,
            eta: state.eta
        )
        completion(entry)
    }

    /// Provide a full timeline of entries.
    ///
    /// When encoding is active, the timeline includes the current state
    /// and requests a refresh after 30 seconds. When idle, it refreshes
    /// after 15 minutes.
    ///
    /// - Parameters:
    ///   - context: The widget context including family and display size.
    ///   - completion: Callback to deliver the timeline.
    func getTimeline(in context: Context, completion: @escaping (Timeline<EncodingProgressEntry>) -> Void) {
        let state = SharedEncodingState.readFromSharedContainer()

        let entry = EncodingProgressEntry(
            date: Date(),
            isEncoding: state.isEncoding,
            progress: state.progress,
            fileName: state.fileName,
            speed: state.speed,
            eta: state.eta
        )

        // Determine refresh interval based on encoding state
        let refreshInterval: TimeInterval = state.isEncoding ? 30 : 900
        let nextUpdate = Date().addingTimeInterval(refreshInterval)

        let timeline = Timeline(
            entries: [entry],
            policy: .after(nextUpdate)
        )

        completion(timeline)
    }
}

// MARK: - EncodingProgressWidgetView

/// The SwiftUI view that renders the encoding progress widget.
///
/// Adapts its layout based on the widget family:
///   - `.systemSmall`: Circular progress ring with percentage only.
///   - `.systemMedium`: Progress ring + file name + speed + ETA.
struct EncodingProgressWidgetView: View {

    /// The timeline entry containing the current encoding state.
    let entry: EncodingProgressEntry

    /// The widget family, used to adapt the layout.
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            // Fall back to medium layout for unsupported families
            mediumView
        }
    }

    // MARK: - Small Widget

    /// Compact view for the small widget family.
    ///
    /// Shows a circular progress ring with the percentage in the centre,
    /// or an idle icon when no encoding is active.
    private var smallView: some View {
        VStack(spacing: 6) {
            if entry.isEncoding {
                ZStack {
                    // Background track
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 8)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: entry.progress)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Percentage text
                    Text("\(Int(entry.progress * 100))%")
                        .font(.title2.monospacedDigit())
                        .fontWeight(.bold)
                }
                .frame(width: 70, height: 70)

                if let fileName = entry.fileName {
                    Text(fileName)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "film.stack")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text("Idle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Medium Widget

    /// Expanded view for the medium widget family.
    ///
    /// Shows the progress ring alongside the file name, speed, and ETA
    /// in a horizontal layout.
    private var mediumView: some View {
        HStack(spacing: 16) {
            if entry.isEncoding {
                // Progress ring on the left
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: entry.progress)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(entry.progress * 100))%")
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                }
                .frame(width: 60, height: 60)

                // Details on the right
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encoding")
                        .font(.headline)

                    if let fileName = entry.fileName {
                        Text(fileName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        if let speed = entry.speed {
                            Label(
                                String(format: "%.1fx", speed),
                                systemImage: "speedometer"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        if let eta = entry.eta {
                            Label(
                                formatETA(eta),
                                systemImage: "clock"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            } else {
                // Idle state
                Image(systemName: "film.stack")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("MeedyaConverter")
                        .font(.headline)

                    Text("No active encoding jobs.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Helpers

    /// Format a time interval as a human-readable ETA string.
    ///
    /// - Parameter interval: Time remaining in seconds.
    /// - Returns: A formatted string like "3:25" or "1:02:15".
    private func formatETA(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - EncodingProgressWidget

/// The WidgetKit widget definition for encoding progress.
///
/// NOTE: This widget must be registered in a WidgetKit extension target
/// (not the main app target) to appear on the macOS desktop or lock screen.
/// The extension target's @main entry point should include this widget in
/// its WidgetBundle:
///
/// ```swift
/// @main
/// struct MeedyaConverterWidgets: WidgetBundle {
///     var body: some Widget {
///         EncodingProgressWidget()
///     }
/// }
/// ```
///
/// The widget uses the shared App Group container to read encoding state
/// written by the main application. Both the app and extension must have
/// the "group.ltd.MWBMpartners.MeedyaConverter" App Group entitlement.
struct EncodingProgressWidget: Widget {

    /// The unique kind identifier for this widget.
    let kind: String = WidgetConstants.widgetKind

    /// The widget's configuration and supported families.
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: EncodingProgressProvider()
        ) { entry in
            EncodingProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("Encoding Progress")
        .description("Monitor MeedyaConverter encoding progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
