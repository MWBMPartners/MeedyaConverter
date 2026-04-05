// ============================================================================
// MeedyaConverter — StatisticsExporter (Issue #363)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - ExportColumn
// ---------------------------------------------------------------------------
/// Selectable columns for CSV/JSON export of encoding statistics.
///
/// Each case maps to a column header in the exported CSV file and a key
/// in the JSON export. Users can include or exclude columns to customise
/// the export output.
///
/// Phase 15 — Export Encoding Statistics to CSV (Issue #363)
public enum ExportColumn: String, CaseIterable, Codable, Sendable, Identifiable {

    /// The date/time when the encode completed.
    case date

    /// The video codec used (e.g., "h265", "av1").
    case codec

    /// The encoder preset (e.g., "medium", "slow").
    case preset

    /// The output resolution label (e.g., "1920x1080").
    case resolution

    /// The source media duration in seconds.
    case inputDuration = "input_duration"

    /// The wall-clock encoding duration in seconds.
    case encodeDuration = "encode_duration"

    /// The encoding speed factor (input duration / encode duration).
    case speed

    /// Whether hardware acceleration was used.
    case hardwareAccelerated = "hardware_accelerated"

    /// Stable identifier for `Identifiable` conformance.
    public var id: String { rawValue }

    /// Human-readable display name for the column.
    public var displayName: String {
        switch self {
        case .date: return "Date"
        case .codec: return "Codec"
        case .preset: return "Preset"
        case .resolution: return "Resolution"
        case .inputDuration: return "Input Duration"
        case .encodeDuration: return "Encode Duration"
        case .speed: return "Speed Factor"
        case .hardwareAccelerated: return "HW Accelerated"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - StatisticsExporter
// ---------------------------------------------------------------------------
/// Exports encoding statistics and history to CSV or JSON format.
///
/// Provides static methods for serialising `EncodingStats` aggregate data
/// and `EncodeHistoryEntry` per-job records into portable interchange
/// formats suitable for spreadsheets, data analysis tools, or archival.
///
/// Features:
/// - CSV export with configurable column selection.
/// - JSON export of aggregate statistics.
/// - Date range filtering to limit the exported history window.
///
/// Phase 15 — Export Encoding Statistics to CSV (Issue #363)
public struct StatisticsExporter: Sendable {

    // MARK: - Date Formatter

    /// ISO 8601 date formatter used for CSV and JSON date fields.
    private static let dateFormatter: ISO8601DateFormatString = "yyyy-MM-dd'T'HH:mm:ssZ"

    // MARK: - CSV Export

    /// Exports encoding history entries as a CSV string.
    ///
    /// Each row represents one completed encode job. The header row uses
    /// the raw column names, and values are comma-separated with proper
    /// escaping for fields that may contain commas or quotes.
    ///
    /// - Parameters:
    ///   - stats: Aggregate statistics (included as a summary comment
    ///     at the top of the CSV).
    ///   - history: The list of individual encode history entries.
    ///   - columns: The columns to include. Defaults to all columns.
    ///   - startDate: Optional start of the date range filter.
    ///   - endDate: Optional end of the date range filter.
    /// - Returns: A CSV-formatted string.
    public static func exportAsCSV(
        stats: EncodingStats,
        history: [EncodeHistoryEntry],
        columns: [ExportColumn] = ExportColumn.allCases,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> String {
        let filtered = filterByDateRange(
            history,
            startDate: startDate,
            endDate: endDate
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines: [String] = []

        // Summary comment header.
        lines.append("# MeedyaConverter Encoding Statistics Export")
        lines.append("# Total Encodes: \(stats.totalEncodes)")
        lines.append("# Successful: \(stats.successfulEncodes)")
        lines.append("# Failed: \(stats.failedEncodes)")
        lines.append("# Total Encoding Time: \(String(format: "%.1f", stats.totalEncodingTime))s")
        lines.append("")

        // Column header row.
        let header = columns.map(\.rawValue).joined(separator: ",")
        lines.append(header)

        // Data rows.
        for entry in filtered {
            let values: [String] = columns.map { column in
                switch column {
                case .date:
                    return formatter.string(from: entry.date)
                case .codec:
                    return csvEscape(entry.codec)
                case .preset:
                    return csvEscape(entry.preset)
                case .resolution:
                    return csvEscape(entry.resolution)
                case .inputDuration:
                    return String(format: "%.2f", entry.inputDuration)
                case .encodeDuration:
                    return String(format: "%.2f", entry.encodeDuration)
                case .speed:
                    return String(format: "%.2f", entry.speedFactor)
                case .hardwareAccelerated:
                    return entry.hardwareAccelerated ? "true" : "false"
                }
            }
            lines.append(values.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Export

    /// Exports aggregate encoding statistics as JSON data.
    ///
    /// The output is a JSON object containing the `EncodingStats` fields
    /// with pretty-printed formatting for human readability.
    ///
    /// - Parameter stats: The aggregate statistics to serialise.
    /// - Returns: UTF-8 encoded JSON data.
    /// - Throws: `EncodingError` if serialisation fails.
    public static func exportAsJSON(stats: EncodingStats) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(stats)
    }

    // MARK: - Filtering

    /// Filters history entries to those within the given date range.
    ///
    /// - Parameters:
    ///   - history: The full list of entries to filter.
    ///   - startDate: If provided, entries before this date are excluded.
    ///   - endDate: If provided, entries after this date are excluded.
    /// - Returns: The filtered subset of entries.
    public static func filterByDateRange(
        _ history: [EncodeHistoryEntry],
        startDate: Date?,
        endDate: Date?
    ) -> [EncodeHistoryEntry] {
        history.filter { entry in
            if let start = startDate, entry.date < start {
                return false
            }
            if let end = endDate, entry.date > end {
                return false
            }
            return true
        }
    }

    // MARK: - Helpers

    /// Escapes a string for safe inclusion in a CSV field.
    ///
    /// If the string contains commas, double-quotes, or newlines, it is
    /// wrapped in double-quotes with internal quotes doubled.
    ///
    /// - Parameter value: The raw string value.
    /// - Returns: A CSV-safe representation of the string.
    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

// ---------------------------------------------------------------------------
// MARK: - ISO8601DateFormatString (Internal Type Alias)
// ---------------------------------------------------------------------------
/// A simple typealias used to document the expected date format string.
/// The actual formatting is handled by `ISO8601DateFormatter`.
private typealias ISO8601DateFormatString = String
