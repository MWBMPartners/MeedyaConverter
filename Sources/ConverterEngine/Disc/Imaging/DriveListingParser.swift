// ============================================================================
// MeedyaConverter — DriveListingParser
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - DriveListingParser

/// Pure parsers for optical-drive discovery output: `cdrdao scanbus`,
/// `drutil list`, and `drutil status`.
///
/// This exists to fix `BurnSettingsView.parseDrutilOutput`, which fabricated
/// `"/dev/rdisk\(count + 1)"` device paths that had no relationship to any
/// real device node. The rule enforced here is simple and load-bearing: a
/// device node is reported *only* when the underlying tool actually printed
/// one. When a listing reveals a drive but not its node — as `drutil list`
/// does — `device` is `nil`, never a guess. A real node is resolved
/// separately, from `drutil status`'s `Name:` line.
public struct DriveListingParser: Sendable {

    /// One detected optical drive.
    public struct DetectedOpticalDrive: Codable, Sendable, Equatable {
        /// The device node, or `nil` when the listing did not reveal one.
        /// NEVER fabricated.
        public let device: String?

        /// Vendor/product description text.
        public let description: String

        public init(device: String?, description: String) {
            self.device = device
            self.description = description
        }
    }

    /// Parse `cdrdao scanbus` output.
    ///
    /// Each drive line has the shape
    /// `/dev/sr0 : TSSTcorp, CDDVDW SH-224DB, SB00` — a device node, a
    /// ` : ` separator, and a vendor/product/revision description. Lines whose
    /// left-hand side is not a `/dev/…` node (headers, blank lines) are
    /// skipped, so only genuine device rows are returned.
    ///
    /// - Parameter output: The full `cdrdao scanbus` output.
    /// - Returns: The detected drives, each with a real device node.
    public static func parseScanbus(_ output: String) -> [DetectedOpticalDrive] {
        var drives: [DetectedOpticalDrive] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }

            let device = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let description = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard device.hasPrefix("/dev/"), !description.isEmpty else { continue }

            drives.append(DetectedOpticalDrive(device: device, description: description))
        }
        return drives
    }

    /// Parse `drutil list` numbered rows.
    ///
    /// `drutil list` prints a header followed by numbered rows such as
    /// `1  HL-DT-ST DVDRW GX40N RQ09 via USB`. It does not print a device
    /// node, so every returned drive has `device == nil` — this is the
    /// regression fix for the old fabricated-path behaviour. Rows are
    /// identified by a leading integer index; the header (no leading integer)
    /// is skipped.
    ///
    /// - Parameter output: The full `drutil list` output.
    /// - Returns: The detected drives, each with `device == nil`.
    public static func parseDrutilList(_ output: String) -> [DetectedOpticalDrive] {
        var drives: [DetectedOpticalDrive] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            // A drive row begins with an integer index; everything else
            // (the "Vendor Product Rev" header, notices) is skipped.
            guard tokens.count >= 2, Int(tokens[0]) != nil else { continue }

            let description = tokens.dropFirst().joined(separator: " ")
            guard !description.isEmpty else { continue }
            drives.append(DetectedOpticalDrive(device: nil, description: description))
        }
        return drives
    }

    /// Extract the device node from a `drutil status` block.
    ///
    /// `drutil status` prints a `Name: /dev/disk4` line for the drive that
    /// currently holds media. Returns that node, or `nil` when there is no
    /// `Name:` line (no media / no drive).
    ///
    /// - Parameter output: The full `drutil status` output.
    /// - Returns: The `/dev/disk…` node, or `nil`.
    public static func parseDrutilStatusDeviceName(_ output: String) -> String? {
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "Name:") else { continue }
            let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            let token = value.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? value
            if token.hasPrefix("/dev/") { return token }
        }
        return nil
    }

    /// Transform a `/dev/diskN` node into its raw counterpart `/dev/rdiskN`.
    ///
    /// Imaging reads go through the raw (unbuffered) node on macOS. This is a
    /// pure string transform: an input that is not a `/dev/disk…` node is
    /// returned unchanged, so it is safe to apply unconditionally.
    ///
    /// - Parameter diskNode: A `/dev/disk…` node (or any other string).
    /// - Returns: The `/dev/rdisk…` node, or the input unchanged.
    public static func rawDeviceNode(forDiskNode diskNode: String) -> String {
        let prefix = "/dev/disk"
        guard diskNode.hasPrefix(prefix) else { return diskNode }
        return "/dev/rdisk" + diskNode.dropFirst(prefix.count)
    }
}
