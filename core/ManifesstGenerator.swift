// File: adaptix/core/ManifestGenerator.swift
// Purpose: Generates adaptive streaming manifests for both HLS (M3U8) and MPEG-DASH (MPD) based on encoded streams.
// Role: Central class to compile available video/audio/subtitle streams into streaming-compatible manifest files.
//
// (C) 2025–present MWBM Partners Ltd (d/b/a MW Services). All rights reserved.
// Version: 1.0.0

import Foundation

/// A struct representing a single stream descriptor for audio, video, or subtitles.
struct MediaStreamDescriptor {
    let type: String           // e.g., video, audio, subtitles
    let codec: String          // e.g., h264, hevc, aac, opus, etc.
    let language: String?      // e.g., "en", "fr" (for audio/subtitles)
    let uri: String            // relative path to media stream file
    let resolution: String?    // e.g., "1920x1080" for video only
    let bitrate: Int           // in kbps
    let frameRate: Double?     // e.g., 29.97 for video only
    let channels: Int?         // for audio only (e.g., 2, 6, 8)
}

/// Manifest generator for HLS and MPEG-DASH adaptive streaming formats.
class ManifestGenerator {

    /// Generates a master M3U8 HLS playlist given a list of media streams.
    func generateHLSManifest(streams: [MediaStreamDescriptor], outputPath: String) throws {
        var manifest = "#EXTM3U\n"
        manifest += "#EXT-X-VERSION:3\n"

        for stream in streams {
            switch stream.type {
            case "video":
                let resolution = stream.resolution ?? ""
                let fr = stream.frameRate ?? 30.0
                manifest += "#EXT-X-STREAM-INF:BANDWIDTH=\(stream.bitrate * 1000),RESOLUTION=\(resolution),FRAME-RATE=\(fr)\n"
                manifest += "\(stream.uri)\n"

            case "audio":
                let lang = stream.language ?? "und"
                manifest += "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"