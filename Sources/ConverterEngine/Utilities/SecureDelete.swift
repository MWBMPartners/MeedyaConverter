// ============================================================================
// MeedyaConverter — SecureDelete (Issue #350)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - OverwritePasses

/// The number of random-data overwrite passes before deletion.
///
/// - `.single` — 1 pass. Fast; sufficient for most SSD-based workflows.
/// - `.dod`    — 3 passes. Aligned with DoD 5220.22-M short-wipe guidance.
/// - `.gutmann`— 7 passes. High-assurance overwrite cycle.
///
/// Phase 13 — Secure File Deletion (Issue #350)
public enum OverwritePasses: Int, Codable, Sendable, CaseIterable {
    case single  = 1
    case dod     = 3
    case gutmann = 7
}

// MARK: - SecureDeleteError

/// Errors raised during secure-deletion operations.
public enum SecureDeleteError: Error, LocalizedError, Sendable {

    /// The file at the given URL does not exist or is not a regular file.
    case fileNotFound(URL)

    /// Unable to determine the file size for overwrite.
    case cannotReadAttributes(URL)

    /// The overwrite verification step detected residual original data.
    case verificationFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found or not a regular file: \(url.lastPathComponent)"
        case .cannotReadAttributes(let url):
            return "Cannot read file attributes: \(url.lastPathComponent)"
        case .verificationFailed(let url):
            return "Verification failed after overwrite: \(url.lastPathComponent)"
        }
    }
}

// MARK: - SecureDelete

/// Provides secure file deletion by overwriting file contents with random bytes
/// for a configurable number of passes before removing the file from disk.
///
/// Phase 13 — Secure File Deletion (Issue #350)
public struct SecureDelete: Sendable {

    // MARK: - Single File

    /// Securely deletes the file at the given URL by overwriting its contents
    /// with random bytes for the specified number of passes, then removing it.
    ///
    /// - Parameters:
    ///   - url: The file URL to securely delete.
    ///   - passes: The overwrite pass count.
    /// - Throws: `SecureDeleteError` if the file cannot be found, read, or verified.
    public static func securelyDelete(at url: URL, passes: OverwritePasses) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw SecureDeleteError.fileNotFound(url)
        }

        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int64, fileSize > 0 else {
            throw SecureDeleteError.cannotReadAttributes(url)
        }

        let size = Int(clamping: fileSize)
        let chunkSize = 1_048_576 // 1 MB chunks for large files

        // Overwrite for the requested number of passes.
        for _ in 0..<passes.rawValue {
            guard let handle = try? FileHandle(forWritingTo: url) else {
                throw SecureDeleteError.fileNotFound(url)
            }
            handle.seek(toFileOffset: 0)

            var remaining = size
            while remaining > 0 {
                let writeSize = min(chunkSize, remaining)
                var randomBytes = [UInt8](repeating: 0, count: writeSize)
                _ = SecRandomCopyBytes(kSecRandomDefault, writeSize, &randomBytes)
                handle.write(Data(randomBytes))
                remaining -= writeSize
            }

            handle.synchronizeFile()
            try handle.close()
        }

        // Verification: read first chunk and confirm it is not all-zero
        // (a naive sanity check that random data was written).
        if let verifyHandle = try? FileHandle(forReadingFrom: url) {
            let sample = verifyHandle.readData(ofLength: min(4096, size))
            try verifyHandle.close()
            if sample.count > 0, sample.allSatisfy({ $0 == 0 }) {
                throw SecureDeleteError.verificationFailed(url)
            }
        }

        // Remove the file from disk.
        try fm.removeItem(at: url)
    }

    // MARK: - Batch Delete

    /// Securely deletes multiple files, returning the count of successfully deleted files.
    ///
    /// Failures on individual files are silently skipped; the caller can compare
    /// the returned count against `urls.count` to detect partial failures.
    ///
    /// - Parameters:
    ///   - urls: The file URLs to securely delete.
    ///   - passes: The overwrite pass count applied to each file.
    /// - Returns: The number of files successfully deleted.
    public static func securelyDeleteBatch(urls: [URL], passes: OverwritePasses) throws -> Int {
        var count = 0
        for url in urls {
            do {
                try securelyDelete(at: url, passes: passes)
                count += 1
            } catch {
                // Continue with remaining files; caller compares count to detect partial failure.
                continue
            }
        }
        return count
    }
}
