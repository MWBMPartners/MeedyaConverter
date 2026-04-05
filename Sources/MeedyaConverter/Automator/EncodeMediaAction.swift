// ============================================================================
// MeedyaConverter — EncodeMediaActionHandler (Hazel/Automator Integration)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides the action handler logic for an Automator action that encodes
// media files using MeedyaConverter's ConverterEngine.
//
// In a full Automator action bundle, this class would be the principal class
// of an AMBundleAction subclass declared in the bundle's Info.plist. For now,
// the handler logic is implemented here so it can be integrated into:
//
//   - Automator workflows (via a future .action bundle target)
//   - Hazel rules (via the app's URL scheme or AppleScript bridge)
//   - Folder Actions (via the macOS Services integration in
//     AutomatorIntegration.swift)
//
// The handler accepts an array of file URLs and an encoding profile name,
// encodes each file sequentially, and returns the output URLs.
//
// Phase 11 / Issue #357
// ---------------------------------------------------------------------------

import Foundation
import ConverterEngine

// MARK: - EncodeMediaActionError

/// Errors specific to the Automator action handler.
enum EncodeMediaActionError: LocalizedError, Sendable {

    /// The encoding engine has not been configured.
    case engineNotConfigured

    /// The specified encoding profile was not found.
    case profileNotFound(String)

    /// No input files were provided.
    case noInputFiles

    /// An individual file failed to encode.
    case encodingFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .engineNotConfigured:
            return "The encoding engine is not configured. Launch MeedyaConverter first."
        case .profileNotFound(let name):
            return "Encoding profile '\(name)' was not found."
        case .noInputFiles:
            return "No input files were provided to the action."
        case .encodingFailed(let url, let reason):
            return "Failed to encode '\(url.lastPathComponent)': \(reason)"
        }
    }
}

// MARK: - EncodeMediaActionHandler

/// Handles batch encoding requests from Automator, Hazel, or Folder Actions.
///
/// This class encapsulates the logic for receiving a set of input media files,
/// encoding each one using a specified profile, and returning the output URLs.
/// It is designed to be the principal class of an Automator action bundle, but
/// can also be invoked programmatically from the Services menu handler or
/// the AppleScript bridge.
///
/// ### Usage
/// ```swift
/// let handler = EncodeMediaActionHandler()
/// handler.engine = myConfiguredEngine
///
/// let outputs = try await handler.handle(
///     input: [videoURL1, videoURL2],
///     profileName: "Web Standard"
/// )
/// // outputs contains URLs to the encoded files
/// ```
///
/// ### Output File Naming
/// Output files are placed in the same directory as the input file, with the
/// profile name appended to the filename stem and the container format's
/// default extension applied:
///   `MyVideo.mov` -> `MyVideo (Web Standard).mp4`
///
/// ### Error Handling
/// If any individual file fails to encode, the handler records the error and
/// continues with the remaining files. The returned array contains only the
/// successfully encoded outputs. If all files fail, the method throws.
@MainActor
final class EncodeMediaActionHandler {

    // MARK: - Properties

    /// The encoding engine to use for probing and encoding.
    ///
    /// Must be set before calling `handle(input:profileName:)`.
    /// Typically wired to the same engine instance used by the GUI.
    var engine: EncodingEngine?

    // MARK: - Action Handler

    /// Encode a batch of media files using the specified profile.
    ///
    /// - Parameters:
    ///   - input: Array of file URLs to encode. Non-existent files are skipped.
    ///   - profileName: The name of the encoding profile to use.
    /// - Returns: Array of output file URLs for successfully encoded files.
    /// - Throws: `EncodeMediaActionError` if the engine is not configured,
    ///   the profile is not found, or all files fail to encode.
    func handle(input: [URL], profileName: String) async throws -> [URL] {
        guard let engine = engine else {
            throw EncodeMediaActionError.engineNotConfigured
        }

        // Look up the profile by name
        guard let profile = engine.profileStore.profile(named: profileName) else {
            throw EncodeMediaActionError.profileNotFound(profileName)
        }

        // Filter to files that actually exist
        let validInputs = input.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validInputs.isEmpty else {
            throw EncodeMediaActionError.noInputFiles
        }

        // Encode each file sequentially
        var outputURLs: [URL] = []
        var errors: [(URL, String)] = []

        for inputURL in validInputs {
            // Generate output URL in the same directory as the input
            let outputURL = Self.outputURL(
                for: inputURL,
                profileName: profileName,
                containerExtension: profile.containerFormat.fileExtensions.first ?? "mp4"
            )

            let jobConfig = EncodingJobConfig(
                id: UUID(),
                inputURL: inputURL,
                outputURL: outputURL,
                profile: profile
            )

            do {
                try await engine.encode(job: jobConfig)
                outputURLs.append(outputURL)
            } catch {
                errors.append((inputURL, error.localizedDescription))
            }
        }

        // If all files failed, throw an error with details
        if outputURLs.isEmpty && !errors.isEmpty {
            let errorDetails = errors
                .map { "  - \($0.0.lastPathComponent): \($0.1)" }
                .joined(separator: "\n")
            throw EncodeMediaActionError.encodingFailed(
                errors.first!.0,
                "All files failed to encode:\n\(errorDetails)"
            )
        }

        return outputURLs
    }

    // MARK: - Output URL Generation

    /// Generate an output URL for an input file using the profile name
    /// and container format extension.
    ///
    /// - Parameters:
    ///   - inputURL: The source file URL.
    ///   - profileName: The encoding profile name (appended to the filename).
    ///   - containerExtension: The file extension for the output container
    ///     (e.g. "mp4", "mkv").
    /// - Returns: A URL in the same directory as the input, with the
    ///   profile name appended and the correct extension.
    static func outputURL(
        for inputURL: URL,
        profileName: String,
        containerExtension: String
    ) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let sanitisedProfile = profileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let outputName = "\(stem) (\(sanitisedProfile)).\(containerExtension)"
        return directory.appendingPathComponent(outputName)
    }
}
