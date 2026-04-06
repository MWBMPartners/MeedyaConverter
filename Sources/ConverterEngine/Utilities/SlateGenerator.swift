// ============================================================================
// MeedyaConverter — SlateGenerator (Issue #343)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - SlateConfig

/// Configuration for a broadcast slate card.
///
/// A slate is a static information card displayed at the head of a broadcast
/// programme. It typically shows the programme title, client, agency, air date,
/// runtime, delivery format, and audio configuration.
///
/// Phase 12 — Slate and Leader Generation for Broadcast Delivery (Issue #343)
public struct SlateConfig: Codable, Sendable {

    // MARK: - Properties

    /// The programme or project title displayed prominently on the slate.
    public var title: String

    /// The client or commissioning entity name (optional).
    public var client: String?

    /// The advertising agency name (optional).
    public var agency: String?

    /// The air date or delivery date string (e.g. "2026-04-05").
    public var date: String

    /// The programme duration string (e.g. "00:30:00").
    public var duration: String

    /// The delivery format description (e.g. "HD 1080i 25fps").
    public var format: String

    /// The audio configuration description (e.g. "Stereo 48kHz 24-bit").
    public var audioConfig: String?

    /// The slate background colour as a hex string (e.g. "#1a1a2e").
    public var backgroundColor: String

    /// The slate text colour as a hex string (e.g. "#ffffff").
    public var textColor: String

    /// The duration in seconds the slate card is held on screen.
    public var durationSeconds: Double

    // MARK: - Initialiser

    /// Create a new slate configuration.
    ///
    /// - Parameters:
    ///   - title: Programme or project title.
    ///   - client: Client name (optional).
    ///   - agency: Agency name (optional).
    ///   - date: Air date or delivery date.
    ///   - duration: Programme duration string.
    ///   - format: Delivery format description.
    ///   - audioConfig: Audio configuration description (optional).
    ///   - backgroundColor: Background hex colour (defaults to "#1a1a2e").
    ///   - textColor: Text hex colour (defaults to "#ffffff").
    ///   - durationSeconds: On-screen hold duration (defaults to 10 seconds).
    public init(
        title: String,
        client: String? = nil,
        agency: String? = nil,
        date: String,
        duration: String,
        format: String,
        audioConfig: String? = nil,
        backgroundColor: String = "#1a1a2e",
        textColor: String = "#ffffff",
        durationSeconds: Double = 10.0
    ) {
        self.title = title
        self.client = client
        self.agency = agency
        self.date = date
        self.duration = duration
        self.format = format
        self.audioConfig = audioConfig
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.durationSeconds = durationSeconds
    }
}

// MARK: - LeaderConfig

/// Configuration for broadcast leader elements (color bars, countdown, black burst).
///
/// A leader sequence precedes the programme content and typically includes
/// SMPTE colour bars with reference tone, a countdown clock, and black burst
/// before the first frame of programme.
///
/// Phase 12 — Slate and Leader Generation for Broadcast Delivery (Issue #343)
public struct LeaderConfig: Codable, Sendable {

    // MARK: - Properties

    /// Duration of the SMPTE colour bars segment in seconds.
    public var colorBarsDuration: Double

    /// Duration of the countdown segment in seconds (typically 10).
    public var countdownDuration: Double

    /// Frequency of the reference tone in Hz (default 1000 Hz / 1 kHz).
    public var toneFrequency: Int

    /// Duration of the reference tone in seconds.
    public var toneDuration: Double

    /// Whether to include a black burst segment after the countdown.
    public var includeBlackBurst: Bool

    /// Duration of the black burst segment in seconds.
    public var blackBurstDuration: Double

    // MARK: - Initialiser

    /// Create a new leader configuration.
    ///
    /// - Parameters:
    ///   - colorBarsDuration: Colour bars duration (defaults to 30 seconds).
    ///   - countdownDuration: Countdown duration (defaults to 10 seconds).
    ///   - toneFrequency: Reference tone frequency in Hz (defaults to 1000).
    ///   - toneDuration: Reference tone duration (defaults to 10 seconds).
    ///   - includeBlackBurst: Whether to include black burst (defaults to `true`).
    ///   - blackBurstDuration: Black burst duration (defaults to 3 seconds).
    public init(
        colorBarsDuration: Double = 30.0,
        countdownDuration: Double = 10.0,
        toneFrequency: Int = 1000,
        toneDuration: Double = 10.0,
        includeBlackBurst: Bool = true,
        blackBurstDuration: Double = 3.0
    ) {
        self.colorBarsDuration = colorBarsDuration
        self.countdownDuration = countdownDuration
        self.toneFrequency = toneFrequency
        self.toneDuration = toneDuration
        self.includeBlackBurst = includeBlackBurst
        self.blackBurstDuration = blackBurstDuration
    }
}

// MARK: - SlateGenerator

/// Generates broadcast-standard leader sequences using FFmpeg.
///
/// Produces FFmpeg argument arrays for each leader segment: SMPTE colour bars
/// with reference tone, a text slate card, a numeric countdown timer, and
/// black burst. These segments can be individually rendered or combined into
/// a complete leader sequence and prepended to programme content.
///
/// All methods return `[String]` argument arrays suitable for passing to
/// `Process.arguments` with `/usr/bin/ffmpeg` as the executable.
///
/// Phase 12 — Slate and Leader Generation for Broadcast Delivery (Issue #343)
public struct SlateGenerator: Sendable {

    // MARK: - Color Bars

    /// Build FFmpeg arguments for generating SMPTE HD colour bars with reference tone.
    ///
    /// Uses the `smptehdbars` test source for video and a sine wave generator
    /// for the 1 kHz reference tone audio.
    ///
    /// - Parameters:
    ///   - outputPath: The file path for the rendered colour bars segment.
    ///   - duration: The duration of the colour bars in seconds.
    ///   - resolution: The output resolution string (e.g. "1920x1080").
    /// - Returns: An array of FFmpeg argument strings.
    public static func buildColorBarsArguments(
        outputPath: String,
        duration: Double,
        resolution: String
    ) -> [String] {
        let (width, height) = parseResolution(resolution)
        return [
            "-y",
            "-f", "lavfi",
            "-i", "smptehdbars=duration=\(duration):size=\(width)x\(height):rate=25",
            "-f", "lavfi",
            "-i", "sine=frequency=1000:duration=\(duration):sample_rate=48000",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            "-shortest",
            outputPath,
        ]
    }

    // MARK: - Slate Card

    /// Build FFmpeg arguments for generating a text slate card.
    ///
    /// Renders the slate information (title, client, agency, date, duration,
    /// format, audio config) as drawtext overlays on a solid colour background.
    /// Silent audio is added to maintain stream consistency when concatenating.
    ///
    /// - Parameters:
    ///   - outputPath: The file path for the rendered slate segment.
    ///   - config: The slate configuration with text and colour settings.
    ///   - resolution: The output resolution string (e.g. "1920x1080").
    /// - Returns: An array of FFmpeg argument strings.
    public static func buildSlateArguments(
        outputPath: String,
        config: SlateConfig,
        resolution: String
    ) -> [String] {
        let (width, height) = parseResolution(resolution)
        let bgHex = sanitiseHex(config.backgroundColor)
        let fgHex = sanitiseHex(config.textColor)

        // Build the slate text lines to overlay.
        var lines: [(label: String, value: String)] = [
            ("TITLE", config.title),
        ]
        if let client = config.client, !client.isEmpty {
            lines.append(("CLIENT", client))
        }
        if let agency = config.agency, !agency.isEmpty {
            lines.append(("AGENCY", agency))
        }
        lines.append(("DATE", config.date))
        lines.append(("DURATION", config.duration))
        lines.append(("FORMAT", config.format))
        if let audio = config.audioConfig, !audio.isEmpty {
            lines.append(("AUDIO", audio))
        }

        // Construct drawtext filter chain. Each line is offset vertically.
        let startY = 200
        let lineSpacing = 60
        var drawTextParts: [String] = []

        for (index, line) in lines.enumerated() {
            let y = startY + (index * lineSpacing)
            let escaped = escapeDrawText("\(line.label): \(line.value)")
            let part = "drawtext=text='\(escaped)':fontcolor=0x\(fgHex)"
                + ":fontsize=36:x=(w-text_w)/2:y=\(y)"
            drawTextParts.append(part)
        }

        let filterChain = drawTextParts.joined(separator: ",")

        return [
            "-y",
            "-f", "lavfi",
            "-i", "color=c=0x\(bgHex):size=\(width)x\(height):duration=\(config.durationSeconds):rate=25",
            "-f", "lavfi",
            "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
            "-vf", filterChain,
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            "-t", "\(config.durationSeconds)",
            "-shortest",
            outputPath,
        ]
    }

    // MARK: - Countdown

    /// Build FFmpeg arguments for generating a countdown timer overlay.
    ///
    /// Renders a numeric countdown (e.g. 10 to 0) using the drawtext filter
    /// with a timer expression. The countdown appears centred on a black
    /// background with optional reference tone audio.
    ///
    /// - Parameters:
    ///   - outputPath: The file path for the rendered countdown segment.
    ///   - config: The leader configuration with countdown and tone settings.
    ///   - resolution: The output resolution string (e.g. "1920x1080").
    /// - Returns: An array of FFmpeg argument strings.
    public static func buildCountdownArguments(
        outputPath: String,
        config: LeaderConfig,
        resolution: String
    ) -> [String] {
        let (width, height) = parseResolution(resolution)
        let countdownStart = Int(config.countdownDuration)

        // The drawtext timer counts from countdownDuration down to 0.
        // Expression: countdownStart - floor(t) where t is the elapsed time.
        let drawText = "drawtext=text='%{eif\\:\(countdownStart)-floor(t)\\:d}'"
            + ":fontcolor=white:fontsize=200:x=(w-text_w)/2:y=(h-text_h)/2"

        return [
            "-y",
            "-f", "lavfi",
            "-i", "color=c=black:size=\(width)x\(height):duration=\(config.countdownDuration):rate=25",
            "-f", "lavfi",
            "-i", "sine=frequency=\(config.toneFrequency):duration=\(config.toneDuration):sample_rate=48000",
            "-vf", drawText,
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            "-shortest",
            outputPath,
        ]
    }

    // MARK: - Full Leader

    /// Build FFmpeg arguments for generating a complete broadcast leader.
    ///
    /// Combines colour bars, slate, countdown, and optional black burst into
    /// a single output file using the FFmpeg concat filter. The segments are
    /// rendered inline via `lavfi` inputs rather than requiring intermediate files.
    ///
    /// - Parameters:
    ///   - outputPath: The file path for the final combined leader.
    ///   - slateConfig: The slate card configuration.
    ///   - leaderConfig: The leader element configuration.
    ///   - resolution: The output resolution string (e.g. "1920x1080").
    /// - Returns: An array of FFmpeg argument strings.
    public static func buildFullLeaderArguments(
        outputPath: String,
        slateConfig: SlateConfig,
        leaderConfig: LeaderConfig,
        resolution: String
    ) -> [String] {
        let (width, height) = parseResolution(resolution)
        let bgHex = sanitiseHex(slateConfig.backgroundColor)
        let fgHex = sanitiseHex(slateConfig.textColor)
        let countdownStart = Int(leaderConfig.countdownDuration)

        // -- Input 0: Color bars video
        // -- Input 1: Color bars tone
        // -- Input 2: Slate background
        // -- Input 3: Slate silence
        // -- Input 4: Countdown background
        // -- Input 5: Countdown tone
        // Optional Input 6/7: Black burst video/silence

        var args: [String] = ["-y"]

        // Input 0: SMPTE HD colour bars
        args.append(contentsOf: [
            "-f", "lavfi",
            "-i", "smptehdbars=duration=\(leaderConfig.colorBarsDuration)"
                + ":size=\(width)x\(height):rate=25",
        ])
        // Input 1: Reference tone for colour bars
        args.append(contentsOf: [
            "-f", "lavfi",
            "-i", "sine=frequency=\(leaderConfig.toneFrequency)"
                + ":duration=\(leaderConfig.colorBarsDuration):sample_rate=48000",
        ])
        // Input 2: Slate colour background
        args.append(contentsOf: [
            "-f", "lavfi",
            "-i", "color=c=0x\(bgHex):size=\(width)x\(height)"
                + ":duration=\(slateConfig.durationSeconds):rate=25",
        ])
        // Input 3: Slate silence
        args.append(contentsOf: [
            "-f", "lavfi",
            "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
        ])
        // Input 4: Countdown black background
        args.append(contentsOf: [
            "-f", "lavfi",
            "-i", "color=c=black:size=\(width)x\(height)"
                + ":duration=\(leaderConfig.countdownDuration):rate=25",
        ])
        // Input 5: Countdown tone
        args.append(contentsOf: [
            "-f", "lavfi",
            "-i", "sine=frequency=\(leaderConfig.toneFrequency)"
                + ":duration=\(leaderConfig.toneDuration):sample_rate=48000",
        ])

        var inputCount = 6

        // Optional Input 6/7: Black burst
        if leaderConfig.includeBlackBurst {
            args.append(contentsOf: [
                "-f", "lavfi",
                "-i", "color=c=black:size=\(width)x\(height)"
                    + ":duration=\(leaderConfig.blackBurstDuration):rate=25",
            ])
            args.append(contentsOf: [
                "-f", "lavfi",
                "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
            ])
            inputCount = 8
        }

        // Build slate drawtext filter lines.
        var slateLines: [(String, String)] = [("TITLE", slateConfig.title)]
        if let client = slateConfig.client, !client.isEmpty {
            slateLines.append(("CLIENT", client))
        }
        if let agency = slateConfig.agency, !agency.isEmpty {
            slateLines.append(("AGENCY", agency))
        }
        slateLines.append(("DATE", slateConfig.date))
        slateLines.append(("DURATION", slateConfig.duration))
        slateLines.append(("FORMAT", slateConfig.format))
        if let audio = slateConfig.audioConfig, !audio.isEmpty {
            slateLines.append(("AUDIO", audio))
        }

        let startY = 200
        let lineSpacing = 60
        var slateDraw = "[2:v]"
        for (i, line) in slateLines.enumerated() {
            let y = startY + (i * lineSpacing)
            let escaped = escapeDrawText("\(line.0): \(line.1)")
            if i > 0 { slateDraw += "," }
            slateDraw += "drawtext=text='\(escaped)':fontcolor=0x\(fgHex)"
                + ":fontsize=36:x=(w-text_w)/2:y=\(y)"
        }
        slateDraw += "[slate_v]"

        // Countdown drawtext filter.
        let countdownDraw = "[4:v]drawtext=text='%{eif\\:\(countdownStart)-floor(t)\\:d}'"
            + ":fontcolor=white:fontsize=200:x=(w-text_w)/2:y=(h-text_h)/2[cd_v]"

        // Build the concat filter.
        var concatInputs = "[0:v][0:a][slate_v][3:a][cd_v][5:a]"
        var segmentCount = 3

        if leaderConfig.includeBlackBurst {
            concatInputs += "[6:v][7:a]"
            segmentCount = 4
        }

        let concatFilter = "\(concatInputs)concat=n=\(segmentCount):v=1:a=1[outv][outa]"

        let filterComplex = "\(slateDraw);\(countdownDraw);\(concatFilter)"

        args.append(contentsOf: [
            "-filter_complex", filterComplex,
            "-map", "[outv]",
            "-map", "[outa]",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            outputPath,
        ])

        // Suppress unused variable warning.
        _ = inputCount

        return args
    }

    // MARK: - Prepend to Video

    /// Build FFmpeg arguments for prepending a leader to programme content.
    ///
    /// Uses the FFmpeg concat demuxer to join the pre-rendered leader file
    /// with the main video file. Both files must share the same codec,
    /// resolution, and frame rate for lossless concatenation.
    ///
    /// - Parameters:
    ///   - leaderPath: The file path of the rendered leader segment.
    ///   - videoPath: The file path of the programme content.
    ///   - outputPath: The file path for the combined output.
    /// - Returns: An array of FFmpeg argument strings.
    public static func prependToVideo(
        leaderPath: String,
        videoPath: String,
        outputPath: String
    ) -> [String] {
        // The concat demuxer requires a text file listing inputs, but
        // we can use the concat protocol for two files directly.
        return [
            "-y",
            "-i", leaderPath,
            "-i", videoPath,
            "-filter_complex", "[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[outv][outa]",
            "-map", "[outv]",
            "-map", "[outa]",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            outputPath,
        ]
    }

    // MARK: - Private Helpers

    /// Parse a resolution string (e.g. "1920x1080") into width and height integers.
    ///
    /// - Parameter resolution: The resolution string in "WIDTHxHEIGHT" format.
    /// - Returns: A tuple of (width, height). Defaults to (1920, 1080) if parsing fails.
    private static func parseResolution(_ resolution: String) -> (Int, Int) {
        let parts = resolution.lowercased().split(separator: "x")
        guard parts.count == 2,
              let w = Int(parts[0]),
              let h = Int(parts[1]) else {
            return (1920, 1080)
        }
        return (w, h)
    }

    /// Sanitise a hex colour string by removing the leading "#" if present.
    ///
    /// - Parameter hex: The hex colour string (e.g. "#ff0000" or "ff0000").
    /// - Returns: The hex string without a leading "#".
    private static func sanitiseHex(_ hex: String) -> String {
        hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    }

    /// Escape special characters for FFmpeg drawtext filter text values.
    ///
    /// FFmpeg drawtext requires certain characters to be escaped with
    /// backslashes: single quotes, colons, backslashes, and semicolons.
    ///
    /// - Parameter text: The raw text string to escape.
    /// - Returns: The escaped text safe for use in drawtext filter expressions.
    private static func escapeDrawText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: ";", with: "\\;")
    }
}
