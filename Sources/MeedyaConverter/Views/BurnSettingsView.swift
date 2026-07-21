// ============================================================================
// MeedyaConverter — BurnSettingsView
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// MARK: - DriveStatus

/// Current status of the optical disc drive.
enum DriveStatus: String {
    case ready = "Ready"
    case busy = "Busy"
    case noDisc = "No Disc"
    case noDrive = "No Drive"

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .busy: return "hourglass"
        case .noDisc: return "opticaldisc"
        case .noDrive: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .green
        case .busy: return .orange
        case .noDisc: return .yellow
        case .noDrive: return .red
        }
    }
}

// MARK: - BurnSettingsView

/// Disc burning settings interface for configuring and initiating physical disc burns.
///
/// Provides drive selection, write speed configuration, verification options,
/// copy count, disc label, and progress display during burning.
///
/// Phase 11 — Burn Settings UI (Issue #145)
struct BurnSettingsView: View {

    // MARK: - Environment

    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var selectedDevicePath: String = ""
    @State private var sourcePath: String = ""
    @State private var discFormat: DiscAuthorFormat = .dvdVideo
    @State private var burnSpeed: BurnSpeedOption = .auto
    @State private var verifyAfterBurn: Bool = true
    @State private var ejectAfterBurn: Bool = true
    @State private var simulate: Bool = false
    @State private var numberOfCopies: Int = 1
    @State private var discLabel: String = ""
    @State private var driveStatus: DriveStatus = .noDrive
    @State private var availableDrives: [DiscDriveInfo] = []

    @State private var isBurning: Bool = false
    @State private var burnProgress: BurnProgress?
    @State private var burnResult: BurnResult?
    @State private var showBurnConfirmation: Bool = false

    // MARK: - Body

    var body: some View {
        Group {
            if availableDrives.isEmpty && driveStatus == .noDrive {
                noDriveView
            } else {
                burnSettingsForm
            }
        }
        .navigationTitle("Disc Burning")
        .onAppear { detectDrives() }
        .alert("Confirm Burn", isPresented: $showBurnConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Burn") { startBurn() }
        } message: {
            Text("Write \"\(discLabel.isEmpty ? "Untitled" : discLabel)\" to disc at \(burnSpeed.displayName) speed?\(simulate ? " (SIMULATION)" : "")")
        }
    }

    // MARK: - No Drive View

    private var noDriveView: some View {
        ContentUnavailableView(
            "No Optical Drive",
            systemImage: "opticaldisc",
            description: Text("Connect an optical disc writer to burn discs. External USB/Thunderbolt drives are supported.")
        )
    }

    // MARK: - Settings Form

    private var burnSettingsForm: some View {
        Form {
            // Drive selection
            Section("Drive") {
                driveSelectionSection
            }

            // Source selection
            Section("Source") {
                sourceSelectionSection
            }

            // Disc settings
            Section("Disc Settings") {
                discSettingsSection
            }

            // Write options
            Section("Write Options") {
                writeOptionsSection
            }

            // Progress (shown during burn)
            if isBurning, let progress = burnProgress {
                Section("Burn Progress") {
                    burnProgressSection(progress)
                }
            }

            // Result (shown after burn)
            if let result = burnResult {
                Section("Result") {
                    burnResultSection(result)
                }
            }

            // Actions
            Section {
                actionButtons
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Drive Selection

    @ViewBuilder
    private var driveSelectionSection: some View {
        Picker("Drive", selection: $selectedDevicePath) {
            if availableDrives.isEmpty {
                Text("No drives detected").tag("")
            }
            ForEach(availableDrives, id: \.devicePath) { drive in
                Text("\(drive.displayName) (\(drive.devicePath))")
                    .tag(drive.devicePath)
            }
        }
        .accessibilityLabel("Select optical disc drive")

        // Drive status indicator
        HStack(spacing: 6) {
            Image(systemName: driveStatus.systemImage)
                .foregroundStyle(driveStatus.color)
                .accessibilityHidden(true)
            Text(driveStatus.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                detectDrives()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .accessibilityLabel("Refresh drive list")
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("Drive status: \(driveStatus.rawValue)")
    }

    // MARK: - Source Selection

    @ViewBuilder
    private var sourceSelectionSection: some View {
        HStack {
            TextField("Source ISO or Directory", text: $sourcePath,
                      prompt: Text("/path/to/image.iso"))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Source file or directory to burn")

            Button("Browse...") {
                browseSource()
            }
        }

        Picker("Disc Format", selection: $discFormat) {
            ForEach(DiscAuthorFormat.allCases, id: \.self) { format in
                Text(format.displayName).tag(format)
            }
        }
        .accessibilityLabel("Disc format type")
    }

    // MARK: - Disc Settings

    @ViewBuilder
    private var discSettingsSection: some View {
        TextField("Disc Label", text: $discLabel,
                  prompt: Text("Volume name"))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Disc volume name")

        Stepper("Number of Copies: \(numberOfCopies)", value: $numberOfCopies, in: 1...99)
            .accessibilityLabel("Number of disc copies to burn")
    }

    // MARK: - Write Options

    @ViewBuilder
    private var writeOptionsSection: some View {
        Picker("Write Speed", selection: $burnSpeed) {
            ForEach(BurnSpeedOption.allCases, id: \.self) { speed in
                Text(speed.displayName).tag(speed)
            }
        }
        .accessibilityLabel("Disc write speed")

        Toggle("Verify after burn", isOn: $verifyAfterBurn)
            .accessibilityLabel("Verify disc data integrity after writing")

        Toggle("Eject disc after burn", isOn: $ejectAfterBurn)
            .accessibilityLabel("Eject disc when burning is complete")

        Toggle("Simulate (dry run)", isOn: $simulate)
            .accessibilityLabel("Perform a simulated burn without writing to disc")

        if simulate {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Simulation mode — no data will be written to disc")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: Simulation mode enabled, no data will be written to disc")
        }
    }

    // MARK: - Progress Display

    @ViewBuilder
    private func burnProgressSection(_ progress: BurnProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(progress.phase.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(progress.percentage)%")
                    .font(.subheadline)
                    .monospacedDigit()
            }

            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .accessibilityLabel("Burn progress")
                .accessibilityValue("\(progress.percentage) percent")

            HStack {
                if let speed = progress.writeSpeed {
                    Text(formatWriteSpeed(speed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(formatBytes(progress.bytesWritten)) / \(formatBytes(progress.totalBytes))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if let bufferFill = progress.bufferFill {
                HStack {
                    Text("Buffer:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(bufferFill), total: 100)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 100)
                    Text("\(bufferFill)%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Write buffer fill")
                .accessibilityValue("\(bufferFill) percent")
            }
        }
    }

    // MARK: - Result Display

    @ViewBuilder
    private func burnResultSection(_ result: BurnResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? .green : .red)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text(result.success ? "Burn Successful" : "Burn Failed")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let message = result.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if result.verified {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Verification passed")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.success ? "Burn successful\(result.verified ? ", verification passed" : "")" : "Burn failed: \(result.message ?? "unknown error")")
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            // Burn button
            Button {
                showBurnConfirmation = true
            } label: {
                Label("Burn Disc", systemImage: "flame")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBurning || selectedDevicePath.isEmpty || sourcePath.isEmpty || driveStatus != .ready)
            .accessibilityLabel("Start disc burning")

            Spacer()

            // Erase button (for RW media)
            Button {
                eraseDisc()
            } label: {
                Label("Erase Disc", systemImage: "trash")
            }
            .disabled(isBurning || selectedDevicePath.isEmpty || driveStatus != .ready)
            .accessibilityLabel("Erase rewritable disc")

            // Eject button
            Button {
                ejectDisc()
            } label: {
                Label("Eject", systemImage: "eject")
            }
            .disabled(isBurning || selectedDevicePath.isEmpty)
            .accessibilityLabel("Eject disc")
        }
    }

    // MARK: - Actions

    /// Detect connected optical drives via `drutil`.
    ///
    /// `BurnSettingsView` is a `struct: View`, so its methods are
    /// implicitly main-actor isolated. A plain `Task { }` here therefore
    /// inherits that isolation (mirrors `VideoTrimmerView.applyTrim()`,
    /// Issue #451): `@State` mutations and the `parseDrutilOutput` call
    /// are direct, MainActor-isolated calls, not `MainActor.run` hops.
    /// Only the genuinely blocking work — launching `drutil` and waiting
    /// for it to exit — runs in a `Task.detached` that returns a
    /// `Sendable` `String` and never touches `self`.
    private func detectDrives() {
        Task {
            do {
                let output = try await Task.detached {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
                    task.arguments = ["list"]

                    let pipe = Pipe()
                    task.standardOutput = pipe
                    task.standardError = pipe

                    try task.run()
                    task.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    return String(data: data, encoding: .utf8) ?? ""
                }.value

                if output.contains("No drives") || output.isEmpty {
                    availableDrives = []
                    driveStatus = .noDrive
                } else {
                    availableDrives = parseDrutilOutput(output)
                    if let first = availableDrives.first {
                        selectedDevicePath = first.devicePath
                        driveStatus = .ready
                    }
                }
            } catch {
                availableDrives = []
                driveStatus = .noDrive
            }
        }
    }

    private func parseDrutilOutput(_ output: String) -> [DiscDriveInfo] {
        var drives: [DiscDriveInfo] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Name:") || trimmed.contains("Vendor:") {
                // Extract drive name from drutil output
                let name = trimmed.replacingOccurrences(of: "Name:", with: "")
                    .replacingOccurrences(of: "Vendor:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    drives.append(DiscDriveInfo(
                        devicePath: "/dev/rdisk\(drives.count + 1)",
                        displayName: name
                    ))
                }
            }
        }

        // If no drives parsed from output but output wasn't empty, add a default
        if drives.isEmpty && !output.contains("No drives") {
            drives.append(DiscDriveInfo(devicePath: "/dev/rdisk1", displayName: "Optical Drive"))
        }

        return drives
    }

    private func browseSource() {
        let panel = NSOpenPanel()
        panel.title = "Select Source to Burn"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourcePath = url.path
    }

    private func startBurn() {
        isBurning = true
        burnResult = nil
        burnProgress = BurnProgress(phase: .preparing, bytesWritten: 0, totalBytes: 0)

        let config = BurnConfig(
            devicePath: selectedDevicePath,
            sourcePath: sourcePath,
            speed: burnSpeed.toBurnSpeed(),
            verify: verifyAfterBurn,
            ejectAfterBurn: ejectAfterBurn,
            simulate: simulate,
            format: discFormat
        )

        // Validate config
        let errors = DiscBurner.validate(config: config)
        if !errors.isEmpty {
            burnResult = BurnResult(success: false, message: errors.joined(separator: "; "), verified: false)
            isBurning = false
            return
        }

        viewModel.appendLog(.info, "Starting disc burn: \(discFormat.displayName) to \(selectedDevicePath)")

        // Capture main-actor-isolated values before entering the detached context.
        let capturedDiscFormat = discFormat
        let capturedSourcePath = sourcePath
        let capturedVerifyAfterBurn = verifyAfterBurn

        // A plain `Task { }` inherits this view's main-actor isolation
        // (mirrors `detectDrives()` above and `VideoTrimmerView.applyTrim()`,
        // Issue #451), so state mutations and `viewModel.appendLog` calls
        // are direct, not `MainActor.run` hops. Argument building is cheap
        // (string formatting only); only the actual `Process` launch and
        // wait are pulled into a `Task.detached` that returns Sendable-only
        // values and never touches `self`.
        Task {
            do {
                let args: [String]
                let executable: String

                switch capturedDiscFormat {
                case .audioCd:
                    executable = "cdrecord"
                    args = DiscBurner.buildAudioCDBurnArguments(config: config, wavFiles: [capturedSourcePath])
                case .dvdVideo, .bluray:
                    executable = "growisofs"
                    args = DiscBurner.buildGrowisofsArguments(config: config)
                default:
                    executable = "hdiutil"
                    args = DiscBurner.buildHdiutilBurnArguments(isoPath: capturedSourcePath, verify: capturedVerifyAfterBurn)
                }

                let (exitCode, errorOutput): (Int32, String?) = try await Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = [executable] + args

                    let outputPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = outputPipe

                    try process.run()
                    process.waitUntilExit()

                    let code = process.terminationStatus
                    let errorOutput: String?
                    if code == 0 {
                        errorOutput = nil
                    } else {
                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        errorOutput = String(data: outputData, encoding: .utf8) ?? "Unknown error"
                    }
                    return (code, errorOutput)
                }.value

                if exitCode == 0 {
                    burnProgress = BurnProgress(phase: .complete, bytesWritten: 0, totalBytes: 0)
                    burnResult = BurnResult(success: true, message: "Disc burned successfully", verified: capturedVerifyAfterBurn)
                    viewModel.appendLog(.info, "Disc burn completed successfully")
                } else {
                    burnProgress = BurnProgress(phase: .failed, bytesWritten: 0, totalBytes: 0)
                    let message = errorOutput ?? "Unknown error"
                    burnResult = BurnResult(success: false, message: message, verified: false)
                    viewModel.appendLog(.error, "Disc burn failed: \(message)")
                }
                isBurning = false
            } catch {
                burnResult = BurnResult(success: false, message: error.localizedDescription, verified: false)
                isBurning = false
                viewModel.appendLog(.error, "Disc burn error: \(error.localizedDescription)")
            }
        }
    }

    /// Mirrors `startBurn()`: a plain `Task { }` inherits main-actor
    /// isolation, so `viewModel.appendLog` is a direct call; only the
    /// `Process` launch/wait is isolated in a `Task.detached`. Per #451.
    private func eraseDisc() {
        let args = DiscBurner.buildBlankArguments(devicePath: selectedDevicePath)
        viewModel.appendLog(.info, "Erasing disc on \(selectedDevicePath)")

        Task {
            do {
                try await Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["cdrecord"] + args

                    try process.run()
                    process.waitUntilExit()
                }.value
                viewModel.appendLog(.info, "Disc erased successfully")
            } catch {
                viewModel.appendLog(.error, "Disc erase failed: \(error.localizedDescription)")
            }
        }
    }

    /// Already Swift 6-safe as written (Issue #451 audit): this closure
    /// captures no `@State`/`self` and never hops back via `MainActor.run`
    /// — it fires the eject process and returns nothing, so `Task.detached`
    /// is exactly the "isolate the genuinely blocking call" half of the
    /// proven pattern, with no outer plain `Task` needed. Left unchanged.
    private func ejectDisc() {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
            process.arguments = DiscBurner.buildDrutilArguments(action: "eject")
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: - Formatters

    private func formatWriteSpeed(_ bytesPerSecond: Double) -> String {
        let mbps = bytesPerSecond / 1_000_000
        return String(format: "%.1f MB/s", mbps)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Types

/// Information about a detected optical disc drive.
struct DiscDriveInfo: Identifiable {
    var id: String { devicePath }
    let devicePath: String
    let displayName: String
}

/// Result of a disc burn operation.
struct BurnResult {
    let success: Bool
    let message: String?
    let verified: Bool
}

/// Write speed options for the UI.
enum BurnSpeedOption: String, CaseIterable {
    case auto = "Automatic"
    case x1 = "1x"
    case x2 = "2x"
    case x4 = "4x"
    case x8 = "8x"
    case x16 = "16x"
    case x24 = "24x"
    case maximum = "Maximum"

    var displayName: String { rawValue }

    func toBurnSpeed() -> BurnSpeed {
        switch self {
        case .auto: return .auto
        case .x1: return .multiplier(1)
        case .x2: return .multiplier(2)
        case .x4: return .multiplier(4)
        case .x8: return .multiplier(8)
        case .x16: return .multiplier(16)
        case .x24: return .multiplier(24)
        case .maximum: return .maximum
        }
    }
}
