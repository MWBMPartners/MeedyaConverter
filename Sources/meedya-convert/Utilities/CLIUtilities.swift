// ============================================================================
// MeedyaConverter — CLI Utilities
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - Exit Codes (Phase 6.9)

/// POSIX-compliant exit codes for the meedya-convert CLI.
///
/// These codes allow scripts and CI pipelines to programmatically
/// determine the reason for failure without parsing error messages.
enum ExitCodes: Int32 {
    /// Command completed successfully.
    case success = 0

    /// General/unspecified error.
    case generalError = 1

    /// Invalid arguments or usage error.
    case invalidArguments = 2

    /// Input file not found or unreadable.
    case inputNotFound = 3

    /// Encoding failed (FFmpeg returned an error).
    case encodingFailed = 4

    /// Output write error (permissions, disk full, path invalid).
    case outputWriteError = 5

    /// Validation failed (manifest validation, profile validation).
    case validationFailed = 6

    /// Interrupted by signal (SIGINT / Ctrl+C).
    case interrupted = 130
}

// MARK: - Stderr Printing

/// Print a message to stderr (keeps stdout clean for machine-readable output).
func printStderr(_ message: String, terminator: String = "\n") {
    FileHandle.standardError.write(
        Data((message + terminator).utf8)
    )
}
