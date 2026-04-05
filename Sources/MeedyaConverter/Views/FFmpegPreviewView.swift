// ============================================================================
// MeedyaConverter — FFmpegPreviewView (Issue #301)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import AppKit
import ConverterEngine

// MARK: - FFmpegPreviewView

/// A sheet view that displays the full FFmpeg command that would be generated
/// for the current encoding configuration.
///
/// Shows the command with syntax highlighting (monospace font, coloured flags)
/// and provides a "Copy to Clipboard" button for easy pasting into a terminal.
struct FFmpegPreviewView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    // MARK: - State

    @State private var copied = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text("FFmpeg Command Preview")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // Command display
            ScrollView {
                if let command = buildCommandString() {
                    commandView(command)
                } else {
                    ContentUnavailableView(
                        "No Command Available",
                        systemImage: "terminal",
                        description: Text("Select a source file and configure output settings to preview the FFmpeg command.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer with copy button
            HStack {
                if let command = buildCommandString() {
                    Text("\(command.arguments.count) arguments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if copied {
                    Label("Copied!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .disabled(buildCommandString() == nil)
                .accessibilityLabel("Copy FFmpeg command to clipboard")
            }
            .padding()
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 400, idealHeight: 500)
    }

    // MARK: - Command View

    @ViewBuilder
    private func commandView(_ command: FFmpegCommandPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Full command as copyable text
            Text(command.fullCommand)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()

            Divider()
                .padding(.horizontal)

            // Syntax-highlighted breakdown
            VStack(alignment: .leading, spacing: 4) {
                Text("Argument Breakdown")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(Array(command.highlightedTokens.enumerated()), id: \.offset) { _, token in
                    HStack(alignment: .top, spacing: 4) {
                        Text(token.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(token.color)
                        if let desc = token.description {
                            Text("— \(desc)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom)
        }
    }

    // MARK: - Command Building

    /// Build the FFmpeg command from the current view model state.
    private func buildCommandString() -> FFmpegCommandPreview? {
        guard let file = viewModel.selectedFile else { return nil }

        let outputDir = viewModel.outputDirectory ?? FileManager.default.temporaryDirectory
        let outputExtension = viewModel.selectedProfile.containerFormat.fileExtensions.first ?? "mkv"
        let baseName = file.fileURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDir
            .appendingPathComponent("\(baseName)_converted")
            .appendingPathExtension(outputExtension)

        let config = EncodingJobConfig(
            inputURL: file.fileURL,
            outputURL: outputURL,
            profile: viewModel.selectedProfile,
            videoStreamIndex: viewModel.selectedVideoStreamIndex,
            audioStreamIndex: viewModel.selectedAudioStreamIndex,
            subtitleStreamIndex: viewModel.selectedSubtitleStreamIndex,
            mapAllStreams: viewModel.mapAllStreams,
            streamMetadata: viewModel.streamMetadataOverrides
        )

        let arguments = config.buildArguments()
        return FFmpegCommandPreview(arguments: arguments)
    }

    // MARK: - Clipboard

    private func copyToClipboard() {
        guard let command = buildCommandString() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.fullCommand, forType: .string)
        copied = true

        // Reset copied indicator after 2 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

// MARK: - FFmpegCommandPreview

/// A parsed FFmpeg command with syntax highlighting metadata.
private struct FFmpegCommandPreview {

    /// The raw argument list from the builder.
    let arguments: [String]

    /// The full shell command string.
    var fullCommand: String {
        let escaped = arguments.map { arg in
            if arg.contains(" ") || arg.contains("(") || arg.contains(")") {
                return "'\(arg)'"
            }
            return arg
        }
        return "ffmpeg " + escaped.joined(separator: " ")
    }

    /// Tokenised and coloured arguments for the breakdown view.
    var highlightedTokens: [HighlightedToken] {
        var tokens: [HighlightedToken] = []
        var index = 0
        let args = arguments

        while index < args.count {
            let arg = args[index]

            if arg == "-i" && index + 1 < args.count {
                // Input flag + path
                tokens.append(HighlightedToken(
                    text: "-i \(args[index + 1])",
                    color: .blue,
                    description: "Input file"
                ))
                index += 2
            } else if arg.hasPrefix("-c:v") || arg.hasPrefix("-codec:v") {
                if index + 1 < args.count {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .green,
                        description: "Video codec"
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .green, description: "Video codec flag"))
                    index += 1
                }
            } else if arg.hasPrefix("-c:a") || arg.hasPrefix("-codec:a") {
                if index + 1 < args.count {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .cyan,
                        description: "Audio codec"
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .cyan, description: "Audio codec flag"))
                    index += 1
                }
            } else if arg.hasPrefix("-b:v") || arg.hasPrefix("-crf") || arg.hasPrefix("-qp") {
                if index + 1 < args.count {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .orange,
                        description: "Video quality/bitrate"
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .orange))
                    index += 1
                }
            } else if arg.hasPrefix("-b:a") {
                if index + 1 < args.count {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .orange,
                        description: "Audio bitrate"
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .orange))
                    index += 1
                }
            } else if arg.hasPrefix("-vf") || arg.hasPrefix("-filter:v") {
                if index + 1 < args.count {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .purple,
                        description: "Video filter chain"
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .purple))
                    index += 1
                }
            } else if arg.hasPrefix("-af") || arg.hasPrefix("-filter:a") {
                if index + 1 < args.count {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .purple,
                        description: "Audio filter chain"
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .purple))
                    index += 1
                }
            } else if arg.hasPrefix("-map") {
                if index + 1 < args.count {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .mint,
                        description: "Stream mapping"
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .mint))
                    index += 1
                }
            } else if arg.hasPrefix("-preset") || arg.hasPrefix("-tune") {
                if index + 1 < args.count {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .yellow,
                        description: arg.hasPrefix("-preset") ? "Encoder preset" : "Encoder tune"
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .yellow))
                    index += 1
                }
            } else if arg.hasPrefix("-") {
                // Generic flag with value
                if index + 1 < args.count && !args[index + 1].hasPrefix("-") {
                    tokens.append(HighlightedToken(
                        text: "\(arg) \(args[index + 1])",
                        color: .secondary
                    ))
                    index += 2
                } else {
                    tokens.append(HighlightedToken(text: arg, color: .secondary))
                    index += 1
                }
            } else {
                // Non-flag argument (likely output path)
                tokens.append(HighlightedToken(
                    text: arg,
                    color: .primary,
                    description: index == args.count - 1 ? "Output file" : nil
                ))
                index += 1
            }
        }

        return tokens
    }
}

// MARK: - HighlightedToken

/// A single syntax-highlighted token in the FFmpeg command breakdown.
private struct HighlightedToken: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
    var description: String?
}
