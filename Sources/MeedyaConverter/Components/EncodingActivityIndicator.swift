// ============================================================================
// MeedyaConverter — EncodingActivityIndicator
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import AppKit
import Combine
import ConverterEngine

// MARK: - EncodingActivityIndicator

/// Provides macOS equivalents of iOS Dynamic Island / Live Activities for
/// encoding progress visibility outside the main window.
///
/// Two system-level indicators are managed:
///   1. **Menu bar status item** — a circular progress ring in the menu bar
///      with a click-to-reveal popover showing detailed encoding progress.
///   2. **Dock tile progress overlay** — a progress bar drawn directly on
///      the app's dock icon, updated in real-time during encoding.
///
/// Both indicators activate automatically when the encoding queue starts
/// and clear themselves when encoding finishes or is cancelled.
///
/// ### Architecture
/// This class is `@MainActor @Observable` to integrate with SwiftUI's
/// Observation framework. It is owned by `AppViewModel` and driven by
/// callbacks from the encoding progress pipeline.
///
/// ### References
/// - GitHub Issue #182 — Dynamic Island / Live Activities (macOS equivalents)
@MainActor @Observable
final class EncodingActivityIndicator {

    // MARK: - Published State

    /// Whether the indicator is currently tracking an encoding job.
    private(set) var isTracking: Bool = false

    /// The current progress fraction (0.0 to 1.0).
    private(set) var currentProgress: Double = 0.0

    /// The current encoding speed multiplier (e.g., 2.5x).
    private(set) var currentSpeed: Double?

    /// The name of the file currently being encoded.
    private(set) var currentFileName: String = ""

    /// Estimated time remaining in seconds.
    private(set) var currentETA: TimeInterval?

    /// Current output bitrate in kbps.
    private(set) var currentBitrate: Double?

    // MARK: - Menu Bar Status Item

    /// The system menu bar status item showing a progress ring.
    private var statusItem: NSStatusItem?

    /// The progress ring view hosted in the status item.
    private var progressRingView: MenuBarProgressRingView?

    /// The popover shown when the status item is clicked.
    private var popover: NSPopover?

    // MARK: - Dock Tile

    /// The custom content view for the dock tile progress overlay.
    private var dockProgressView: DockProgressView?

    // MARK: - Observation

    /// Cancellable for observing EncodingJobState changes.
    private var jobObservation: AnyCancellable?

    // MARK: - Lifecycle

    /// Begin tracking an encoding job, activating menu bar and dock indicators.
    ///
    /// - Parameter jobState: The encoding job state to observe for progress updates.
    func startTracking(jobState: EncodingJobState) {
        guard !isTracking else { return }
        isTracking = true
        currentProgress = 0.0
        currentSpeed = nil
        currentETA = nil
        currentBitrate = nil
        currentFileName = jobState.config.inputURL.lastPathComponent

        setupMenuBarItem()
        setupDockProgress()

        // Observe published properties on the job state
        jobObservation = jobState.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateProgress(
                    fraction: jobState.progress,
                    speed: jobState.speed,
                    fileName: jobState.config.inputURL.lastPathComponent
                )
                self.currentETA = jobState.eta
                self.currentBitrate = jobState.currentBitrate
            }
        }
    }

    /// Update progress indicators with new values.
    ///
    /// Called from the encoding progress callback in `AppViewModel`.
    ///
    /// - Parameters:
    ///   - fraction: Progress fraction from 0.0 to 1.0.
    ///   - speed: Optional encoding speed multiplier.
    ///   - fileName: The name of the file being encoded.
    func updateProgress(fraction: Double, speed: Double?, fileName: String) {
        currentProgress = fraction
        currentSpeed = speed
        currentFileName = fileName

        // Update menu bar progress ring
        progressRingView?.progress = fraction

        // Update dock tile progress bar
        dockProgressView?.progress = fraction
        NSApp.dockTile.display()
    }

    /// Stop tracking and remove all system-level indicators.
    ///
    /// Clears the menu bar status item and restores the default dock tile.
    func stopTracking() {
        isTracking = false
        jobObservation?.cancel()
        jobObservation = nil

        // Dismiss popover if visible
        popover?.performClose(nil)
        popover = nil

        // Remove menu bar status item
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        progressRingView = nil

        // Clear dock tile
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.badgeLabel = nil
        NSApp.dockTile.display()

        // Reset state
        currentProgress = 0.0
        currentSpeed = nil
        currentFileName = ""
        currentETA = nil
        currentBitrate = nil
    }

    // MARK: - Menu Bar Setup

    /// Create and configure the menu bar status item with a progress ring.
    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        let ringView = MenuBarProgressRingView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        ringView.progress = 0.0
        progressRingView = ringView

        item.button?.addSubview(ringView)
        ringView.translatesAutoresizingMaskIntoConstraints = false
        if let button = item.button {
            NSLayoutConstraint.activate([
                ringView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                ringView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ringView.widthAnchor.constraint(equalToConstant: 18),
                ringView.heightAnchor.constraint(equalToConstant: 18),
            ])
        }

        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.toolTip = "MeedyaConverter — Encoding in Progress"
    }

    /// Toggle the detail popover when the menu bar item is clicked.
    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(relativeTo: sender)
        }
    }

    /// Display the encoding detail popover anchored to the status bar button.
    private func showPopover(relativeTo sender: NSStatusBarButton) {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 280, height: 140)
        pop.behavior = .transient
        pop.animates = true

        let popoverView = MenuBarPopoverView(indicator: self)
        pop.contentViewController = NSHostingController(rootView: popoverView)

        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover = pop
    }

    // MARK: - Dock Tile Setup

    /// Create and install the dock tile progress overlay.
    private func setupDockProgress() {
        let progressView = DockProgressView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128)
        )
        progressView.progress = 0.0
        dockProgressView = progressView

        NSApp.dockTile.contentView = progressView
        NSApp.dockTile.display()
    }
}

// MARK: - MenuBarProgressRingView

/// A custom `NSView` that draws a circular progress ring in the menu bar.
///
/// The ring animates from 0% to 100% as encoding progresses, using the
/// system accent colour against a faint track.
final class MenuBarProgressRingView: NSView {

    /// The current progress fraction (0.0 to 1.0).
    var progress: Double = 0.0 {
        didSet { needsDisplay = true }
    }

    /// Line width for the progress ring stroke.
    private let lineWidth: CGFloat = 2.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let inset = lineWidth / 2.0 + 1.0
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0

        // Track (background ring)
        let trackPath = NSBezierPath()
        trackPath.appendArc(
            withCenter: centre,
            radius: radius,
            startAngle: 0,
            endAngle: 360
        )
        trackPath.lineWidth = lineWidth
        NSColor.tertiaryLabelColor.setStroke()
        trackPath.stroke()

        // Progress arc — starts at 12 o'clock (90°), drawn clockwise
        guard progress > 0 else { return }
        let startAngle: CGFloat = 90
        let endAngle = startAngle - CGFloat(progress) * 360.0

        let progressPath = NSBezierPath()
        progressPath.appendArc(
            withCenter: centre,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        progressPath.lineWidth = lineWidth
        progressPath.lineCapStyle = .round
        NSColor.controlAccentColor.setStroke()
        progressPath.stroke()
    }
}

// MARK: - MenuBarPopoverView

/// SwiftUI view displayed inside the menu bar popover with detailed
/// encoding progress information.
///
/// Shows file name, percentage, speed, ETA, and bitrate in a compact layout.
struct MenuBarPopoverView: View {

    /// The activity indicator providing live state.
    let indicator: EncodingActivityIndicator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Encoding")
                    .font(.headline)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Encoding in progress")

            Divider()

            // File name
            Text(indicator.currentFileName)
                .font(.subheadline)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityLabel("File: \(indicator.currentFileName)")

            // Progress bar
            ProgressView(value: indicator.currentProgress)
                .accessibilityLabel("Encoding progress")
                .accessibilityValue("\(Int(indicator.currentProgress * 100)) percent")

            // Stats row
            HStack {
                Text("\(Int(indicator.currentProgress * 100))%")
                    .monospacedDigit()
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                if let speed = indicator.currentSpeed {
                    Text(String(format: "%.1fx", speed))
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(format: "Speed: %.1f times realtime", speed))
                }

                if let eta = indicator.currentETA {
                    let mins = Int(eta) / 60
                    let secs = Int(eta) % 60
                    Text("ETA \(mins):\(String(format: "%02d", secs))")
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Estimated time remaining: \(mins) minutes \(secs) seconds")
                }
            }

            // Bitrate row
            if let bitrate = indicator.currentBitrate {
                Text(String(format: "%.0f kbps", bitrate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(String(format: "Bitrate: %.0f kilobits per second", bitrate))
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

// MARK: - DockProgressView

/// A custom `NSView` that draws a progress bar overlay on the dock icon.
///
/// Renders a translucent pill-shaped progress bar near the bottom of the
/// dock tile, similar to macOS system download progress indicators.
final class DockProgressView: NSView {

    /// The current progress fraction (0.0 to 1.0).
    var progress: Double = 0.0 {
        didSet { needsDisplay = true }
    }

    /// Height of the progress bar.
    private let barHeight: CGFloat = 12.0

    /// Horizontal inset from the dock tile edges.
    private let horizontalInset: CGFloat = 8.0

    /// Corner radius of the progress bar.
    private let cornerRadius: CGFloat = 4.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw the application icon first
        if let appIcon = NSApp.applicationIconImage {
            appIcon.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }

        // Progress bar track — positioned near the bottom of the dock tile
        let trackRect = NSRect(
            x: horizontalInset,
            y: 8,
            width: bounds.width - (horizontalInset * 2),
            height: barHeight
        )

        // Track background (semi-transparent dark pill)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.withAlphaComponent(0.6).setFill()
        trackPath.fill()

        // Track border
        NSColor.white.withAlphaComponent(0.3).setStroke()
        trackPath.lineWidth = 0.5
        trackPath.stroke()

        // Filled progress portion
        guard progress > 0 else { return }
        let fillWidth = max(barHeight, trackRect.width * CGFloat(progress))
        let fillRect = NSRect(
            x: trackRect.origin.x,
            y: trackRect.origin.y,
            width: fillWidth,
            height: barHeight
        )

        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.controlAccentColor.setFill()
        fillPath.fill()
    }
}
