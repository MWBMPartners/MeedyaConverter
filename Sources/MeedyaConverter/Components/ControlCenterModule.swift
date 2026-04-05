// ============================================================================
// MeedyaConverter — ControlCenterModule (Status Bar Popover Widget)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides a Control Center-style NSStatusItem widget with an NSPopover
// that displays encoding progress, queue status, and quick controls.
//
// macOS does not provide a public third-party API for Control Center modules.
// This implementation uses an NSStatusItem with a custom NSPopover to create
// a comparable user experience — a compact, always-accessible overlay that
// shows encoding status at a glance.
//
// Features:
//   - Circular progress ring rendered in the menu bar icon area.
//   - NSPopover with current job name, progress bar, speed, ETA.
//   - Queue count badge showing pending jobs.
//   - CPU usage indicator for the FFmpeg process.
//   - Quick pause/resume and stop buttons.
//   - Auto-show popover when encoding starts (configurable).
//   - Auto-hide popover when idle (configurable).
//
// Builds on the existing MenuBarController (Issue #281) by adding the
// popover overlay and progress ring. MenuBarController handles the basic
// status item and dropdown menu; this class adds the richer popover.
//
// Phase 11 / Issue #359
// ---------------------------------------------------------------------------

import AppKit
import SwiftUI
import ConverterEngine

// MARK: - ControlCenterWidget

/// An enhanced menu bar widget that provides a Control Center-like popover
/// for monitoring and controlling encoding progress.
///
/// This class manages an `NSStatusItem` with a custom button view that
/// renders a circular progress ring, and an `NSPopover` that shows detailed
/// encoding status with quick controls.
///
/// ### Integration
/// Create an instance during app launch and call `install()` to add the
/// status item to the menu bar. Update encoding state via the published
/// properties — the progress ring and popover update automatically.
///
/// ```swift
/// let widget = ControlCenterWidget()
/// widget.install()
///
/// // Update from encoding progress callbacks:
/// widget.currentFileName = "MyVideo.mov"
/// widget.progress = 0.45
/// widget.speed = 2.3
/// widget.eta = 180
/// widget.queueCount = 3
/// ```
///
/// ### Thread Safety
/// All properties and methods are `@MainActor` because NSStatusItem and
/// NSPopover must be accessed on the main thread.
@MainActor @Observable
final class ControlCenterWidget {

    // MARK: - Encoding State Properties

    /// Whether encoding is currently in progress.
    ///
    /// When this transitions from `false` to `true` and `autoShowOnEncode`
    /// is enabled, the popover is shown automatically.
    var isEncoding: Bool = false {
        didSet {
            if isEncoding && !oldValue && autoShowOnEncode {
                showPopover()
            }
            if !isEncoding && oldValue && autoHideWhenIdle {
                hidePopover()
            }
            updateStatusItemIcon()
        }
    }

    /// The name of the file currently being encoded.
    var currentFileName: String?

    /// Encoding progress as a fraction from 0.0 to 1.0.
    var progress: Double = 0.0 {
        didSet {
            updateStatusItemIcon()
        }
    }

    /// Current encoding speed (e.g. 2.5 means 2.5x realtime).
    var speed: Double?

    /// Estimated time remaining in seconds.
    var eta: TimeInterval?

    /// Number of jobs waiting in the queue (excluding the current job).
    var queueCount: Int = 0

    /// Approximate CPU usage percentage for the encoding process (0-100).
    var cpuUsage: Double = 0.0

    /// Whether the current encoding job is paused.
    var isPaused: Bool = false

    // MARK: - Configuration Properties

    /// Whether to automatically show the popover when encoding starts.
    ///
    /// Persisted in UserDefaults under the key "controlCenterAutoShow".
    var autoShowOnEncode: Bool {
        didSet {
            UserDefaults.standard.set(autoShowOnEncode, forKey: "controlCenterAutoShow")
        }
    }

    /// Whether to automatically hide the popover when encoding finishes
    /// and the queue is empty.
    ///
    /// Persisted in UserDefaults under the key "controlCenterAutoHide".
    var autoHideWhenIdle: Bool {
        didSet {
            UserDefaults.standard.set(autoHideWhenIdle, forKey: "controlCenterAutoHide")
        }
    }

    // MARK: - Callbacks

    /// Called when the user taps the pause/resume button in the popover.
    var onPauseResume: (() -> Void)?

    /// Called when the user taps the stop button in the popover.
    var onStop: (() -> Void)?

    // MARK: - Private Properties

    /// The NSStatusItem managed by this widget.
    private var statusItem: NSStatusItem?

    /// The popover displayed when the user clicks the status item.
    private var popover: NSPopover?

    /// Event monitor for clicks outside the popover (to dismiss it).
    private var eventMonitor: Any?

    // MARK: - Initialiser

    /// Creates a new ControlCenterWidget with persisted configuration.
    init() {
        self.autoShowOnEncode = UserDefaults.standard.object(forKey: "controlCenterAutoShow") as? Bool ?? true
        self.autoHideWhenIdle = UserDefaults.standard.object(forKey: "controlCenterAutoHide") as? Bool ?? false
    }

    // MARK: - Public API

    /// Install the status item in the system menu bar.
    ///
    /// Creates the NSStatusItem with a custom button showing the app icon.
    /// When encoding is active, the icon is overlaid with a circular
    /// progress ring.
    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "film.stack",
                accessibilityDescription: "MeedyaConverter"
            )
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }

        statusItem = item
    }

    /// Remove the status item from the system menu bar.
    func uninstall() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        dismissPopover()
    }

    /// Show the popover anchored to the status item button.
    func showPopover() {
        guard let button = statusItem?.button else { return }

        if popover == nil {
            let pop = NSPopover()
            pop.contentSize = NSSize(width: 280, height: 260)
            pop.behavior = .transient
            pop.animates = true
            pop.contentViewController = NSHostingController(
                rootView: ControlCenterPopoverView(widget: self)
            )
            popover = pop
        }

        popover?.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )

        // Monitor for outside clicks to dismiss
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hidePopover()
        }
    }

    /// Hide the popover if it is currently shown.
    func hidePopover() {
        popover?.performClose(nil)
        dismissEventMonitor()
    }

    /// Update encoding state from an EncodingJobState.
    ///
    /// Convenience method that extracts all relevant properties from
    /// a job state object. Call this from the encoding progress callback.
    ///
    /// - Parameter jobState: The current encoding job's state, or nil
    ///   if no job is active.
    func updateFromJobState(_ jobState: EncodingJobState?) {
        if let job = jobState {
            isEncoding = job.status == .encoding || job.status == .paused
            isPaused = job.status == .paused
            currentFileName = job.config.inputURL.lastPathComponent
            progress = job.progress
            speed = job.speed
            eta = job.eta
        } else {
            isEncoding = false
            isPaused = false
            currentFileName = nil
            progress = 0.0
            speed = nil
            eta = nil
        }
    }

    // MARK: - Private Methods

    /// Handle clicks on the status item button.
    @objc private func statusItemClicked(_ sender: Any?) {
        if popover?.isShown == true {
            hidePopover()
        } else {
            showPopover()
        }
    }

    /// Update the status item icon to reflect the current progress.
    ///
    /// When encoding is active, the icon is replaced with a circular
    /// progress ring. When idle, the standard film.stack icon is restored.
    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }

        if isEncoding {
            // Create a progress ring image for the menu bar
            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                let lineWidth: CGFloat = 2.0
                let insetRect = rect.insetBy(dx: lineWidth, dy: lineWidth)

                // Background ring (grey track)
                let trackPath = NSBezierPath(
                    ovalIn: insetRect
                )
                trackPath.lineWidth = lineWidth
                NSColor.tertiaryLabelColor.setStroke()
                trackPath.stroke()

                // Progress arc
                let center = NSPoint(x: rect.midX, y: rect.midY)
                let radius = min(insetRect.width, insetRect.height) / 2
                let startAngle: CGFloat = 90 // 12 o'clock position
                let endAngle = startAngle - CGFloat(self.progress * 360)

                let arcPath = NSBezierPath()
                arcPath.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: true
                )
                arcPath.lineWidth = lineWidth
                arcPath.lineCapStyle = .round
                NSColor.controlAccentColor.setStroke()
                arcPath.stroke()

                return true
            }
            image.isTemplate = false
            button.image = image
        } else {
            // Restore default icon
            let icon = NSImage(
                systemSymbolName: "film.stack",
                accessibilityDescription: "MeedyaConverter"
            )
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
            button.image = icon
        }
    }

    /// Remove the global event monitor used to dismiss the popover.
    private func dismissPopover() {
        popover?.close()
        popover = nil
        dismissEventMonitor()
    }

    /// Remove the global click event monitor.
    private func dismissEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - ControlCenterPopoverView

/// The SwiftUI view displayed inside the NSPopover.
///
/// Shows current encoding status with progress, speed, ETA, queue count,
/// CPU usage, and quick pause/stop controls.
private struct ControlCenterPopoverView: View {

    // MARK: - Properties

    /// Reference to the widget for reading state and invoking actions.
    let widget: ControlCenterWidget

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "film.stack")
                    .font(.title3)
                Text("MeedyaConverter")
                    .font(.headline)
                Spacer()
            }

            Divider()

            if widget.isEncoding {
                encodingView
            } else {
                idleView
            }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Subviews

    /// View shown when encoding is active.
    private var encodingView: some View {
        VStack(spacing: 10) {
            // File name
            if let fileName = widget.currentFileName {
                Text(fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Circular progress ring with percentage
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: widget.progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: widget.progress)

                Text("\(Int(widget.progress * 100))%")
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
            }
            .frame(width: 80, height: 80)

            // Speed and ETA
            HStack {
                if let speed = widget.speed {
                    Label(
                        String(format: "%.1fx", speed),
                        systemImage: "speedometer"
                    )
                    .font(.caption)
                }

                Spacer()

                if let eta = widget.eta {
                    Label(
                        formatETA(eta),
                        systemImage: "clock"
                    )
                    .font(.caption)
                }
            }

            // Queue count and CPU
            HStack {
                if widget.queueCount > 0 {
                    Label(
                        "\(widget.queueCount) queued",
                        systemImage: "list.number"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Label(
                    String(format: "CPU %.0f%%", widget.cpuUsage),
                    systemImage: "cpu"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            // Quick controls
            HStack(spacing: 16) {
                Button {
                    widget.onPauseResume?()
                } label: {
                    Label(
                        widget.isPaused ? "Resume" : "Pause",
                        systemImage: widget.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    widget.onStop?()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// View shown when no encoding is active.
    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Idle")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("No active encoding jobs.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
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
