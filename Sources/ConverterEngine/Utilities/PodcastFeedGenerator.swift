// ============================================================================
// MeedyaConverter — PodcastFeedGenerator (Issue #349)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Provides RSS 2.0 feed generation with iTunes/Apple Podcasts namespace
// extensions. This module enables MeedyaConverter users to generate valid
// podcast feeds directly from their encoded audio files, turning the app
// into a complete podcast production pipeline.
//
// Components:
//   - ``PodcastFeedConfig``  — feed-level metadata (title, author, etc.)
//   - ``PodcastEpisode``     — per-episode metadata and audio reference
//   - ``PodcastFeedGenerator`` — static methods for RSS generation,
//     validation, and episode auto-population from file metadata.
//
// Phase 14 — RSS/Podcast Feed Generation (Issue #349)
// ---------------------------------------------------------------------------

import Foundation

// ---------------------------------------------------------------------------
// MARK: - PodcastFeedConfig
// ---------------------------------------------------------------------------
/// Configuration for a podcast RSS feed, containing all feed-level metadata.
///
/// Maps to the `<channel>` element in RSS 2.0 and the corresponding
/// `<itunes:*>` elements for Apple Podcasts compatibility.
public struct PodcastFeedConfig: Codable, Sendable {

    /// The podcast title (maps to `<title>`).
    public var title: String

    /// A plain-text description of the podcast (maps to `<description>`).
    public var description: String

    /// The podcast author name (maps to `<itunes:author>`).
    public var author: String

    /// The podcast website URL (maps to `<link>`).
    public var link: URL

    /// Optional artwork image URL (maps to `<itunes:image>`).
    ///
    /// Apple Podcasts requires artwork to be at least 1400x1400 pixels,
    /// with a maximum of 3000x3000.
    public var imageURL: URL?

    /// The language code for the podcast (maps to `<language>`).
    ///
    /// Uses ISO 639-1 format (e.g., "en", "en-us", "de").
    public var language: String

    /// The iTunes category for the podcast (maps to `<itunes:category>`).
    ///
    /// Must be a valid Apple Podcasts category (e.g., "Technology",
    /// "Arts", "Comedy").
    public var category: String

    /// Whether the podcast contains explicit content.
    ///
    /// Maps to `<itunes:explicit>` — `true` or `false`.
    public var explicit: Bool

    // MARK: - Initialiser

    /// Creates a new podcast feed configuration.
    ///
    /// - Parameters:
    ///   - title: The podcast title.
    ///   - description: A plain-text description.
    ///   - author: The author name.
    ///   - link: The podcast website URL.
    ///   - imageURL: Optional artwork image URL.
    ///   - language: ISO 639-1 language code. Defaults to "en".
    ///   - category: iTunes category string. Defaults to "Technology".
    ///   - explicit: Whether the content is explicit. Defaults to `false`.
    public init(
        title: String,
        description: String,
        author: String,
        link: URL,
        imageURL: URL? = nil,
        language: String = "en",
        category: String = "Technology",
        explicit: Bool = false
    ) {
        self.title = title
        self.description = description
        self.author = author
        self.link = link
        self.imageURL = imageURL
        self.language = language
        self.category = category
        self.explicit = explicit
    }
}

// ---------------------------------------------------------------------------
// MARK: - PodcastEpisode
// ---------------------------------------------------------------------------
/// Metadata for a single podcast episode, corresponding to an `<item>`
/// element in the RSS feed.
public struct PodcastEpisode: Identifiable, Codable, Sendable, Equatable {

    /// Unique identifier for this episode.
    public let id: UUID

    /// The episode title (maps to `<title>`).
    public var title: String

    /// A plain-text description of the episode (maps to `<description>`).
    public var description: String

    /// The URL where the audio file is hosted (maps to `<enclosure url>`).
    public var audioURL: URL

    /// The duration of the episode in seconds (maps to `<itunes:duration>`).
    public var duration: TimeInterval

    /// The file size in bytes (maps to `<enclosure length>`).
    public var fileSize: Int64

    /// The publication date (maps to `<pubDate>`).
    public var publishDate: Date

    /// Optional season number (maps to `<itunes:season>`).
    public var season: Int?

    /// Optional episode number (maps to `<itunes:episode>`).
    public var episode: Int?

    /// The MIME type of the audio file (maps to `<enclosure type>`).
    ///
    /// Common values: "audio/mpeg" (MP3), "audio/mp4" (AAC/M4A),
    /// "audio/ogg" (Ogg Vorbis), "audio/x-wav" (WAV).
    public var mimeType: String

    // MARK: - Initialiser

    /// Creates a new podcast episode.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - title: The episode title.
    ///   - description: A plain-text description.
    ///   - audioURL: The URL where the audio file is hosted.
    ///   - duration: Duration in seconds.
    ///   - fileSize: File size in bytes.
    ///   - publishDate: Publication date. Defaults to now.
    ///   - season: Optional season number.
    ///   - episode: Optional episode number.
    ///   - mimeType: MIME type of the audio file. Defaults to "audio/mpeg".
    public init(
        id: UUID = UUID(),
        title: String,
        description: String,
        audioURL: URL,
        duration: TimeInterval,
        fileSize: Int64,
        publishDate: Date = Date(),
        season: Int? = nil,
        episode: Int? = nil,
        mimeType: String = "audio/mpeg"
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.audioURL = audioURL
        self.duration = duration
        self.fileSize = fileSize
        self.publishDate = publishDate
        self.season = season
        self.episode = episode
        self.mimeType = mimeType
    }
}

// ---------------------------------------------------------------------------
// MARK: - PodcastFeedGenerator
// ---------------------------------------------------------------------------
/// Generates valid RSS 2.0 feeds with iTunes/Apple Podcasts namespace
/// extensions for podcast distribution.
///
/// All methods are static and the struct carries no state, making it
/// safe to use from any concurrency context.
///
/// ### Usage
/// ```swift
/// let config = PodcastFeedConfig(
///     title: "My Podcast",
///     description: "A great podcast",
///     author: "Jane Doe",
///     link: URL(string: "https://example.com")!
/// )
/// let episodes = [PodcastEpisode(...)]
/// let xml = PodcastFeedGenerator.generateRSSFeed(config: config, episodes: episodes)
/// ```
public struct PodcastFeedGenerator: Sendable {

    // MARK: - RSS Generation

    /// Generates a valid RSS 2.0 XML feed with iTunes extensions.
    ///
    /// The output conforms to the RSS 2.0 specification and includes
    /// Apple Podcasts namespace elements (`itunes:*`) for compatibility
    /// with podcast directories.
    ///
    /// - Parameters:
    ///   - config: The feed-level metadata configuration.
    ///   - episodes: An array of episodes to include, sorted by publish
    ///     date (most recent first) in the output.
    /// - Returns: A valid RSS 2.0 XML string.
    public static func generateRSSFeed(
        config: PodcastFeedConfig,
        episodes: [PodcastEpisode]
    ) -> String {
        // Sort episodes by publish date, newest first.
        let sortedEpisodes = episodes.sorted { $0.publishDate > $1.publishDate }

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"
             xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
             xmlns:content="http://purl.org/rss/1.0/modules/content/"
             xmlns:atom="http://www.w3.org/2005/Atom">
          <channel>
            <title>\(escapeXML(config.title))</title>
            <description>\(escapeXML(config.description))</description>
            <link>\(escapeXML(config.link.absoluteString))</link>
            <language>\(escapeXML(config.language))</language>
            <lastBuildDate>\(rfc822Date(Date()))</lastBuildDate>
            <generator>MeedyaConverter by MWBM Partners Ltd</generator>
            <itunes:author>\(escapeXML(config.author))</itunes:author>
            <itunes:summary>\(escapeXML(config.description))</itunes:summary>
            <itunes:category text="\(escapeXMLAttribute(config.category))"/>
            <itunes:explicit>\(config.explicit ? "true" : "false")</itunes:explicit>

        """

        // Add artwork if provided.
        if let imageURL = config.imageURL {
            xml += "    <itunes:image href=\"\(escapeXMLAttribute(imageURL.absoluteString))\"/>\n"
            xml += "    <image>\n"
            xml += "      <url>\(escapeXML(imageURL.absoluteString))</url>\n"
            xml += "      <title>\(escapeXML(config.title))</title>\n"
            xml += "      <link>\(escapeXML(config.link.absoluteString))</link>\n"
            xml += "    </image>\n"
        }

        // Add each episode as an <item>.
        for ep in sortedEpisodes {
            xml += generateEpisodeItem(ep)
        }

        xml += "  </channel>\n"
        xml += "</rss>\n"

        return xml
    }

    // MARK: - Validation

    /// Performs basic structural validation on an RSS XML string.
    ///
    /// Checks for required elements (`<rss>`, `<channel>`, `<title>`,
    /// `<description>`, `<link>`) and common issues. This is not a full
    /// XML schema validation but catches the most frequent mistakes.
    ///
    /// - Parameter xml: The RSS XML string to validate.
    /// - Returns: An array of validation error/warning messages. An empty
    ///   array indicates the feed passed all checks.
    public static func validateFeed(_ xml: String) -> [String] {
        var issues: [String] = []

        // Check for XML declaration.
        if !xml.hasPrefix("<?xml") {
            issues.append("Missing XML declaration (<?xml version=\"1.0\"?>)")
        }

        // Check for RSS root element.
        if !xml.contains("<rss") {
            issues.append("Missing <rss> root element")
        }

        // Check for channel element.
        if !xml.contains("<channel>") {
            issues.append("Missing <channel> element")
        }

        // Check for required channel children.
        let requiredElements = ["<title>", "<description>", "<link>"]
        for element in requiredElements {
            if !xml.contains(element) {
                issues.append("Missing required element: \(element)")
            }
        }

        // Check for iTunes namespace declaration.
        if !xml.contains("xmlns:itunes") {
            issues.append("Missing iTunes namespace declaration (xmlns:itunes)")
        }

        // Check for at least one episode item.
        if !xml.contains("<item>") {
            issues.append("Warning: Feed contains no <item> (episode) elements")
        }

        // Check for enclosure in items (required for podcast episodes).
        if xml.contains("<item>") && !xml.contains("<enclosure") {
            issues.append("Warning: Episodes missing <enclosure> element (required for audio)")
        }

        // Check for balanced RSS tags.
        if !xml.contains("</rss>") {
            issues.append("Missing closing </rss> tag")
        }

        if !xml.contains("</channel>") {
            issues.append("Missing closing </channel> tag")
        }

        return issues
    }

    // MARK: - Episode Auto-Population

    /// Creates a ``PodcastEpisode`` from an audio file, auto-populating
    /// metadata from the file's attributes.
    ///
    /// Reads the file size from the filesystem and infers the MIME type
    /// from the file extension. Duration must be provided separately
    /// (or can be probed via FFprobe in a higher-level caller).
    ///
    /// - Parameters:
    ///   - url: The local file URL of the audio file.
    ///   - title: The episode title to use.
    /// - Returns: A populated ``PodcastEpisode``, or `nil` if the file
    ///   cannot be read.
    public static func episodeFromFile(url: URL, title: String) -> PodcastEpisode? {
        let fileManager = FileManager.default

        // Read file attributes for size.
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        // Infer MIME type from file extension.
        let mimeType = mimeTypeForExtension(url.pathExtension)

        // Attempt to read duration via AVFoundation if available.
        // For now, default to 0 — the caller can update this via FFprobe.
        let duration: TimeInterval = 0

        return PodcastEpisode(
            title: title,
            description: "",
            audioURL: url,
            duration: duration,
            fileSize: fileSize,
            publishDate: Date(),
            mimeType: mimeType
        )
    }

    // MARK: - Private Helpers

    /// Generates the `<item>` XML block for a single episode.
    ///
    /// - Parameter episode: The episode to render.
    /// - Returns: An XML string representing the `<item>` element.
    private static func generateEpisodeItem(_ episode: PodcastEpisode) -> String {
        var item = "    <item>\n"
        item += "      <title>\(escapeXML(episode.title))</title>\n"
        item += "      <description>\(escapeXML(episode.description))</description>\n"
        item += "      <enclosure url=\"\(escapeXMLAttribute(episode.audioURL.absoluteString))\" "
        item += "length=\"\(episode.fileSize)\" "
        item += "type=\"\(escapeXMLAttribute(episode.mimeType))\"/>\n"
        item += "      <guid isPermaLink=\"false\">\(episode.id.uuidString)</guid>\n"
        item += "      <pubDate>\(rfc822Date(episode.publishDate))</pubDate>\n"
        item += "      <itunes:duration>\(formatDuration(episode.duration))</itunes:duration>\n"

        if let season = episode.season {
            item += "      <itunes:season>\(season)</itunes:season>\n"
        }

        if let episodeNumber = episode.episode {
            item += "      <itunes:episode>\(episodeNumber)</itunes:episode>\n"
        }

        item += "    </item>\n"
        return item
    }

    /// Escapes special XML characters in text content.
    ///
    /// Replaces `&`, `<`, `>`, `"`, and `'` with their XML entity
    /// equivalents to prevent injection and malformed XML.
    ///
    /// - Parameter string: The raw string to escape.
    /// - Returns: The XML-safe escaped string.
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Escapes special characters for XML attribute values.
    ///
    /// - Parameter string: The raw attribute value.
    /// - Returns: The escaped attribute value.
    private static func escapeXMLAttribute(_ string: String) -> String {
        escapeXML(string)
    }

    /// Formats a date in RFC 822 format as required by RSS 2.0.
    ///
    /// Example output: `Sat, 05 Apr 2026 14:30:00 +0000`
    ///
    /// - Parameter date: The date to format.
    /// - Returns: The RFC 822 formatted date string.
    private static func rfc822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Formats a duration in seconds as HH:MM:SS for iTunes.
    ///
    /// - Parameter seconds: The duration in seconds.
    /// - Returns: A formatted duration string (e.g., "01:23:45").
    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// Infers a MIME type from a file extension.
    ///
    /// - Parameter ext: The file extension (without the leading dot).
    /// - Returns: The corresponding MIME type string.
    private static func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a", "aac", "mp4":
            return "audio/mp4"
        case "ogg", "oga":
            return "audio/ogg"
        case "wav":
            return "audio/x-wav"
        case "flac":
            return "audio/flac"
        case "opus":
            return "audio/opus"
        default:
            return "audio/mpeg"
        }
    }
}
