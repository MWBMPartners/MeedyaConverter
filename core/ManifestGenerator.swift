// File: adaptix/core/ManifestGenerator.swift
// Purpose: Generates adaptive streaming manifests for both HLS (M3U8) and MPEG-DASH (MPD) based on encoded streams.
// Role: Central class to compile available video/audio/subtitle streams into streaming-compatible manifest files.
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

/// A struct representing a single stream descriptor for audio, video, or subtitles.
struct MediaStreamDescriptor: Codable {
    let type: String           // e.g., video, audio, subtitles
    let codec: String          // e.g., h264, hevc, aac, opus, etc.
    let language: String?      // e.g., "en", "fr" (for audio/subtitles)
    let uri: String            // relative path to media stream file
    let resolution: String?    // e.g., "1920x1080" for video only
    let bitrate: Int           // in kbps
    let frameRate: Double?     // e.g., 29.97 for video only
    let channels: Int?         // for audio only (e.g., 2, 6, 8)
    let segmentDuration: Double? // for HLS/DASH segments (default 6 seconds)
}

/// Manifest generator for HLS and MPEG-DASH adaptive streaming formats.
class ManifestGenerator {

    // MARK: - HLS Manifest Generation

    /// Generates a master M3U8 HLS playlist given a list of media streams.
    /// - Parameters:
    ///   - streams: Array of MediaStreamDescriptor objects
    ///   - outputPath: File path where the master playlist will be saved
    ///   - encryption: Optional AES-128 encryption parameters
    /// - Throws: File writing errors
    func generateHLSManifest(streams: [MediaStreamDescriptor],
                           outputPath: String,
                           encryption: EncryptionConfig? = nil) throws {
        var manifest = "#EXTM3U\n"
        manifest += "#EXT-X-VERSION:7\n"
        manifest += "#EXT-X-INDEPENDENT-SEGMENTS\n\n"

        // Group audio streams by language
        let audioStreams = streams.filter { $0.type == "audio" }
        let videoStreams = streams.filter { $0.type == "video" }
        let subtitleStreams = streams.filter { $0.type == "subtitles" }

        // Define audio groups
        if !audioStreams.isEmpty {
            for (index, stream) in audioStreams.enumerated() {
                let lang = stream.language ?? "und"
                let name = languageName(for: lang)
                let groupID = "audio-\(stream.codec)"
                let isDefault = index == 0 ? "YES" : "NO"
                let autoSelect = index == 0 ? "YES" : "NO"

                manifest += "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"\(groupID)\",NAME=\"\(name)\","
                manifest += "LANGUAGE=\"\(lang)\",DEFAULT=\(isDefault),AUTOSELECT=\(autoSelect),"
                manifest += "CHANNELS=\"\(stream.channels ?? 2)\","
                manifest += "URI=\"\(stream.uri)\"\n"
            }
            manifest += "\n"
        }

        // Define subtitle groups
        if !subtitleStreams.isEmpty {
            for stream in subtitleStreams {
                let lang = stream.language ?? "und"
                let name = languageName(for: lang)
                let groupID = "subs"

                manifest += "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(groupID)\",NAME=\"\(name)\","
                manifest += "LANGUAGE=\"\(lang)\",DEFAULT=NO,AUTOSELECT=YES,"
                manifest += "URI=\"\(stream.uri)\"\n"
            }
            manifest += "\n"
        }

        // Define video variants
        for stream in videoStreams.sorted(by: { $0.bitrate > $1.bitrate }) {
            let bandwidth = stream.bitrate * 1000
            let resolution = stream.resolution ?? "1920x1080"
            let frameRate = stream.frameRate ?? 30.0
            let codec = hlsCodecString(for: stream.codec)

            var variantLine = "#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth)"
            variantLine += ",RESOLUTION=\(resolution)"
            variantLine += ",FRAME-RATE=\(frameRate)"
            variantLine += ",CODECS=\"\(codec)\""

            if !audioStreams.isEmpty, let audioCodec = audioStreams.first?.codec {
                let audioGroupID = "audio-\(audioCodec)"
                variantLine += ",AUDIO=\"\(audioGroupID)\""
            }

            if !subtitleStreams.isEmpty {
                variantLine += ",SUBTITLES=\"subs\""
            }

            manifest += "\(variantLine)\n"
            manifest += "\(stream.uri)\n"
        }

        // Write master playlist
        try manifest.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    /// Generates a variant playlist (media playlist) for a specific stream
    /// - Parameters:
    ///   - stream: The media stream descriptor
    ///   - segments: Array of segment file paths
    ///   - outputPath: Where to save the variant playlist
    ///   - encryption: Optional AES-128 encryption config
    func generateHLSVariantPlaylist(stream: MediaStreamDescriptor,
                                   segments: [String],
                                   outputPath: String,
                                   encryption: EncryptionConfig? = nil) throws {
        var playlist = "#EXTM3U\n"
        playlist += "#EXT-X-VERSION:7\n"
        playlist += "#EXT-X-TARGETDURATION:\(Int(ceil(stream.segmentDuration ?? 6.0)))\n"
        playlist += "#EXT-X-MEDIA-SEQUENCE:0\n"

        if let enc = encryption {
            playlist += "#EXT-X-KEY:METHOD=AES-128,URI=\"\(enc.keyURI)\""
            if let iv = enc.iv {
                playlist += ",IV=0x\(iv)"
            }
            playlist += "\n"
        }

        for segment in segments {
            playlist += "#EXTINF:\(stream.segmentDuration ?? 6.0),\n"
            playlist += "\(segment)\n"
        }

        playlist += "#EXT-X-ENDLIST\n"
        try playlist.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    // MARK: - MPEG-DASH Manifest Generation

    /// Generates an MPEG-DASH MPD manifest
    /// - Parameters:
    ///   - streams: Array of all media streams
    ///   - outputPath: Path to save the MPD file
    ///   - duration: Total media duration in seconds
    ///   - encryption: Optional DRM configuration
    func generateDASHManifest(streams: [MediaStreamDescriptor],
                            outputPath: String,
                            duration: Double,
                            encryption: EncryptionConfig? = nil) throws {
        var mpd = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="urn:mpeg:dash:schema:mpd:2011 DASH-MPD.xsd"
             type="static"
             mediaPresentationDuration="PT\(Int(duration))S"
             minBufferTime="PT2S"
             profiles="urn:mpeg:dash:profile:isoff-on-demand:2011">

        """

        // Add Period
        mpd += "  <Period id=\"0\" duration=\"PT\(Int(duration))S\">\n"

        // Video Adaptation Set
        let videoStreams = streams.filter { $0.type == "video" }
        if !videoStreams.isEmpty {
            mpd += "    <AdaptationSet id=\"0\" contentType=\"video\" mimeType=\"video/mp4\" "
            mpd += "subsegmentAlignment=\"true\" bitstreamSwitching=\"true\">\n"

            for (index, stream) in videoStreams.enumerated() {
                let codec = dashCodecString(for: stream.codec)
                let resolution = stream.resolution ?? "1920x1080"
                let components = resolution.split(separator: "x")
                let width = String(components[0])
                let height = String(components[1])

                mpd += "      <Representation id=\"video-\(index)\" "
                mpd += "bandwidth=\"\(stream.bitrate * 1000)\" "
                mpd += "codecs=\"\(codec)\" "
                mpd += "width=\"\(width)\" "
                mpd += "height=\"\(height)\" "

                if let fps = stream.frameRate {
                    mpd += "frameRate=\"\(fps)\" "
                }

                mpd += ">\n"
                mpd += "        <BaseURL>\(stream.uri)</BaseURL>\n"
                mpd += "        <SegmentBase indexRange=\"0-1000\" />\n"
                mpd += "      </Representation>\n"
            }

            mpd += "    </AdaptationSet>\n"
        }

        // Audio Adaptation Sets (one per language)
        let audioStreams = streams.filter { $0.type == "audio" }
        let audioByLanguage = Dictionary(grouping: audioStreams) { $0.language ?? "und" }

        for (index, (language, streams)) in audioByLanguage.enumerated() {
            mpd += "    <AdaptationSet id=\"\(index + 1)\" contentType=\"audio\" "
            mpd += "mimeType=\"audio/mp4\" lang=\"\(language)\">\n"

            for (streamIndex, stream) in streams.enumerated() {
                let codec = dashCodecString(for: stream.codec)

                mpd += "      <Representation id=\"audio-\(language)-\(streamIndex)\" "
                mpd += "bandwidth=\"\(stream.bitrate * 1000)\" "
                mpd += "codecs=\"\(codec)\" "
                mpd += "audioSamplingRate=\"48000\" "

                if let channels = stream.channels {
                    mpd += ">\n"
                    mpd += "        <AudioChannelConfiguration "
                    mpd += "schemeIdUri=\"urn:mpeg:dash:23003:3:audio_channel_configuration:2011\" "
                    mpd += "value=\"\(channels)\" />\n"
                    mpd += "        <BaseURL>\(stream.uri)</BaseURL>\n"
                    mpd += "        <SegmentBase indexRange=\"0-1000\" />\n"
                    mpd += "      </Representation>\n"
                } else {
                    mpd += ">\n"
                    mpd += "        <BaseURL>\(stream.uri)</BaseURL>\n"
                    mpd += "        <SegmentBase indexRange=\"0-1000\" />\n"
                    mpd += "      </Representation>\n"
                }
            }

            mpd += "    </AdaptationSet>\n"
        }

        // Subtitle Adaptation Sets
        let subtitleStreams = streams.filter { $0.type == "subtitles" }
        let subtitlesByLanguage = Dictionary(grouping: subtitleStreams) { $0.language ?? "und" }

        for (index, (language, streams)) in subtitlesByLanguage.enumerated() {
            let adaptationID = audioByLanguage.count + index + 1
            mpd += "    <AdaptationSet id=\"\(adaptationID)\" contentType=\"text\" "
            mpd += "mimeType=\"application/mp4\" lang=\"\(language)\">\n"

            for (streamIndex, stream) in streams.enumerated() {
                mpd += "      <Representation id=\"subtitle-\(language)-\(streamIndex)\" "
                mpd += "bandwidth=\"\(stream.bitrate * 1000)\">\n"
                mpd += "        <BaseURL>\(stream.uri)</BaseURL>\n"
                mpd += "        <SegmentBase indexRange=\"0-1000\" />\n"
                mpd += "      </Representation>\n"
            }

            mpd += "    </AdaptationSet>\n"
        }

        mpd += "  </Period>\n"
        mpd += "</MPD>\n"

        try mpd.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Helper Methods

    /// Converts codec name to HLS-compatible codec string
    private func hlsCodecString(for codec: String) -> String {
        switch codec.lowercased() {
        case "h264", "avc":
            return "avc1.640028" // High Profile Level 4.0
        case "h265", "hevc":
            return "hev1.1.6.L120.B0" // Main Profile
        case "vp9":
            return "vp09.00.40.08"
        case "av1":
            return "av01.0.05M.08"
        case "aac":
            return "mp4a.40.2"
        case "he-aac":
            return "mp4a.40.5"
        case "he-aacv2":
            return "mp4a.40.29"
        case "opus":
            return "opus"
        case "ac3":
            return "ac-3"
        case "eac3", "ec3":
            return "ec-3"
        default:
            return codec
        }
    }

    /// Converts codec name to DASH-compatible codec string
    private func dashCodecString(for codec: String) -> String {
        switch codec.lowercased() {
        case "h264", "avc":
            return "avc1.640028"
        case "h265", "hevc":
            return "hev1.1.6.L120.B0"
        case "vp9":
            return "vp09.00.40.08"
        case "av1":
            return "av01.0.05M.08"
        case "aac":
            return "mp4a.40.2"
        case "he-aac":
            return "mp4a.40.5"
        case "he-aacv2":
            return "mp4a.40.29"
        case "opus":
            return "opus"
        case "ac3":
            return "ac-3"
        case "eac3", "ec3":
            return "ec-3"
        default:
            return codec
        }
    }

    /// Returns human-readable language name for ISO 639 code
    private func languageName(for code: String) -> String {
        let languages: [String: String] = [
            "en": "English",
            "en-US": "English (US)",
            "en-GB": "English (UK)",
            "es": "Spanish",
            "fr": "French",
            "de": "German",
            "it": "Italian",
            "pt": "Portuguese",
            "pt-BR": "Portuguese (Brazil)",
            "ru": "Russian",
            "ja": "Japanese",
            "ko": "Korean",
            "zh": "Chinese",
            "ar": "Arabic",
            "hi": "Hindi",
            "und": "Undefined"
        ]
        return languages[code] ?? code.uppercased()
    }
}

// MARK: - Supporting Structures

/// Configuration for AES-128 HLS encryption or DASH DRM
struct EncryptionConfig: Codable {
    let method: String          // "AES-128" for HLS, "cenc" for DASH
    let keyURI: String          // URI to key file
    let iv: String?             // Initialization vector (hex string)
    let keyFormat: String?      // e.g., "identity" for HLS
    let keyFormatVersions: String? // e.g., "1" for HLS
}
