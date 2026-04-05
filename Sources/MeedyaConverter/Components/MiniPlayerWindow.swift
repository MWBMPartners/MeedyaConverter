// ============================================================================
// MeedyaConverter — MiniPlayerWindow
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides a floating mini player window that shows encoding progress in a
// compact, always-on-top panel.
//
// Features:
//   - NSPanel configured as a floating, utility-style window.
//   - Compact layout (~300x120): file name, progress bar, speed, ETA.
//   - Automatically appears when the main window is minimised.
//   - Click to restore the main window.
//   - Show / hide / toggle API for programmatic control.
//   - @Observable for SwiftUI reactivity.
//
// Phase 11 — Mini Player / Floating Progress Window (Issue #280)
// ---------------------------------------------------------------------------

import AppKit
import SwiftUI

// MARK: - MiniPlayerController

/// Controls the floating mini player `NSPanel` that displays encoding
/// progress when the main window is minimised or hidden.
///
/// This class is `@MainActor` because `NSPanel` and all AppKit window
/// APIs must be accessed on the main thread. It is `@Observable` so
/// SwiftUI views and other components can react to property changes.
///
/// ### Lifecycle
/// Call ``show()`` to present the panel, ``hide()`` to dismiss it,
/// or ``toggle()`` to flip visibility. The panel is created lazily
/// on first show and reused thereafter.
@MainActor @Observable
final class MiniPlayerController {

    // MARK: - Properties

    /// Whether the mini player panel is currently visible.
    var isVisible: Bool = false

    /// The file name currently being encoded (displayed in the panel).
    var currentFileName: String = ""

    /// Encoding progress as a fraction (0.0–1.0).
    var progress: Double = 0

    /// Current encoding speed (e.g. "2.5x").
    var speed: String = ""

    /// Estimated time remaining (e.g. "3m 12s").
    var eta: String = ""

    /// The floating NSPanel instance. Created lazily on first ``show()``.
    private var panel: NSPanel?

    /// Hosting controller for the SwiftUI mini player view.
    private var hostingController: NSHostingController<MiniPlayerContentView>?

    // MARK: - Panel Configuration

    /// Desired panel width.
    private static let panelWidth: CGFloat = 300

    /// Desired panel height.
    private static let panelHeight: CGFloat = 120

    // MARK: - Public Methods

    /// Shows the mini player panel.
    ///
    /// If the panel has not been created yet, it is initialised with the
    /// correct style mask and level. The panel is ordered front and
    /// ``isVisible`` is set to `true`.
    func show() {
        if panel == nil {
            createPanel()
        }
        updateContent()
        panel?.orderFront(nil)
        isVisible = true
    }

    /// Hides the mini player panel.
    ///
    /// Orders the panel out and sets ``isVisible`` to `false`.
    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    /// Toggles the mini player panel visibility.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Updates the displayed progress information.
    ///
    /// Call this periodically during encoding to keep the mini player
    /// in sync with the current job's progress.
    ///
    /// - Parameters:
    ///   - fileName: Name of the file being encoded.
    ///   - progress: Progress fraction (0.0–1.0).
    ///   - speed: Speed string (e.g. "2.5x").
    ///   - eta: ETA string (e.g. "3m 12s").
    func updateProgress(
        fileName: String,
        progress: Double,
        speed: String,
        eta: String
    ) {
        self.currentFileName = fileName
        self.progress = progress
        self.speed = speed
        self.eta = eta

        if isVisible {
            updateContent()
        }
    }

    /// Restores the main application window and hides the mini player.
    ///
    /// Activates the app, un-minimises the main window if needed,
    /// and hides the panel.
    func restoreMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window !== panel {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            break
        }
        hide()
    }

    // MARK: - Private Helpers

    /// Creates the floating `NSPanel` with utility style and always-on-top
    /// level.
    private func createPanel() {
        let contentView = MiniPlayerContentView(controller: self)
        let hosting = NSHostingController(rootView: contentView)

        let styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .utilityWindow,
            .nonactivatingPanel
        ]

        let newPanel = NSPanel(
            contentRect: NSRect(
                x: 0, y: 0,
                width: Self.panelWidth,
                height: Self.panelHeight
            ),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        newPanel.title = "MeedyaConverter"
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isMovableByWindowBackground = true
        newPanel.hidesOnDeactivate = false
        newPanel.contentViewController = hosting
        newPanel.isReleasedWhenClosed = false

        // Position in top-right corner of the screen.
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let origin = NSPoint(
                x: screenFrame.maxX - Self.panelWidth - 20,
                y: screenFrame.maxY - Self.panelHeight - 20
            )
            newPanel.setFrameOrigin(origin)
        }

        self.panel = newPanel
        self.hostingController = hosting
    }

    /// Updates the hosting controller's root view with current values.
    private func updateContent() {
        hostingController?.rootView = MiniPlayerContentView(controller: self)
    }
}

// MARK: - MiniPlayerContentView

/// The SwiftUI content displayed inside the floating mini player panel.
///
/// Shows the current file name (truncated), a progress bar, encoding
/// speed, ETA, and an expand button to restore the main window.
private struct MiniPlayerContentView: View {

    /// Reference to the controller for reading state and performing actions.
    let controller: MiniPlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File name
            HStack {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)

                Text(controller.currentFileName.isEmpty
                     ? "No active encoding"
                     : controller.currentFileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Expand button to restore main window.
                Button {
                    controller.restoreMainWindow()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Restore main window")
            }

            // Progress bar
            ProgressView(value: controller.progress, total: 1.0)
                .progressViewStyle(.linear)

            // Speed and ETA
            HStack {
                Label(controller.speed.isEmpty ? "--" : controller.speed,
                      systemImage: "speedometer")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Label(controller.eta.isEmpty ? "--" : controller.eta,
                      systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(controller.progress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .frame(width: 280, height: 100)
    }
}

// MARK: - MiniPlayerView

/// A standalone SwiftUI view that can be embedded in other views to display
/// the same compact progress information as the floating mini player.
///
/// This is useful for embedding mini player status in settings or the
/// main window toolbar area without requiring the floating panel.
struct MiniPlayerView: View {

    // MARK: - Properties

    /// The mini player controller providing state.
    let controller: MiniPlayerController

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File name row
            HStack {
                Image(systemName: "film")
                    .foregroundStyle(.blue)

                Text(controller.currentFileName.isEmpty
                     ? "No active encoding"
                     : controller.currentFileName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    controller.toggle()
                } label: {
                    Image(systemName: controller.isVisible
                          ? "pip.exit"
                          : "pip.enter")
                }
                .buttonStyle(.borderless)
                .help(controller.isVisible
                      ? "Hide mini player"
                      : "Show mini player")
            }

            // Progress bar
            ProgressView(value: controller.progress, total: 1.0)
                .progressViewStyle(.linear)

            // Stats row
            HStack {
                Label(controller.speed.isEmpty ? "--" : controller.speed,
                      systemImage: "speedometer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Label(controller.eta.isEmpty ? "--" : controller.eta,
                      systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(controller.progress * 100))%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
