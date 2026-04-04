// ============================================================================
// MeedyaConverter — DiscBurner
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - BurnSpeed

/// Disc burn speed options.
public enum BurnSpeed: Codable, Sendable {
    /// Automatic speed selection.
    case auto

    /// Specific speed multiplier (e.g., 4x, 8x, 16x).
    case multiplier(Int)

    /// Maximum available speed.
    case maximum

    /// cdrecord speed value.
    public var cdrecordValue: String {
        switch self {
        case .auto: return "0"
        case .multiplier(let x): return "\(x)"
        case .maximum: return "99"
        }
    }
}

// MARK: - BurnConfig

/// Configuration for a physical disc burning operation.
public struct BurnConfig: Codable, Sendable {
    /// Device path of the disc writer.
    public var devicePath: String

    /// Source to burn (ISO file or directory).
    public var sourcePath: String

    /// Burn speed.
    public var speed: BurnSpeed

    /// Whether to verify the burn after writing.
    public var verify: Bool

    /// Whether to eject the disc after burning.
    public var ejectAfterBurn: Bool

    /// Whether to perform a simulation (dry run).
    public var simulate: Bool

    /// Disc format being burned.
    public var format: DiscAuthorFormat

    public init(
        devicePath: String,
        sourcePath: String,
        speed: BurnSpeed = .auto,
        verify: Bool = true,
        ejectAfterBurn: Bool = true,
        simulate: Bool = false,
        format: DiscAuthorFormat = .dvdVideo
    ) {
        self.devicePath = devicePath
        self.sourcePath = sourcePath
        self.speed = speed
        self.verify = verify
        self.ejectAfterBurn = ejectAfterBurn
        self.simulate = simulate
        self.format = format
    }
}

// MARK: - BurnProgress

/// Progress information for a disc burning operation.
public struct BurnProgress: Sendable {
    /// Current phase of the burn.
    public var phase: BurnPhase

    /// Bytes written so far.
    public var bytesWritten: Int64

    /// Total bytes to write.
    public var totalBytes: Int64

    /// Write speed in bytes/second.
    public var writeSpeed: Double?

    /// Buffer fill percentage.
    public var bufferFill: Int?

    /// Overall progress fraction (0.0–1.0).
    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesWritten) / Double(totalBytes)
    }

    /// Progress percentage (0–100).
    public var percentage: Int {
        Int(fraction * 100)
    }

    public init(
        phase: BurnPhase = .preparing,
        bytesWritten: Int64 = 0,
        totalBytes: Int64 = 0,
        writeSpeed: Double? = nil,
        bufferFill: Int? = nil
    ) {
        self.phase = phase
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
        self.writeSpeed = writeSpeed
        self.bufferFill = bufferFill
    }
}

// MARK: - BurnPhase

/// Phases of a disc burning operation.
public enum BurnPhase: String, Codable, Sendable {
    case preparing = "preparing"
    case blanking = "blanking"
    case leadIn = "lead_in"
    case writing = "writing"
    case fixating = "fixating"
    case verifying = "verifying"
    case complete = "complete"
    case failed = "failed"

    /// Display name.
    public var displayName: String {
        switch self {
        case .preparing: return "Preparing"
        case .blanking: return "Blanking disc"
        case .leadIn: return "Writing lead-in"
        case .writing: return "Writing data"
        case .fixating: return "Fixating disc"
        case .verifying: return "Verifying burn"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }
}

// MARK: - DiscBurner

/// Builds command-line arguments for physical disc burning using
/// cdrecord, wodim, growisofs, and platform-native APIs.
///
/// Supports:
/// - Audio CD burning (cdrecord/wodim)
/// - Data CD/DVD burning (cdrecord/growisofs)
/// - Blu-ray burning (growisofs)
/// - Disc blanking (CD-RW, DVD-RW)
/// - Burn verification
/// - macOS DRBurn framework integration
///
/// Phase 9
public struct DiscBurner: Sendable {

    // MARK: - cdrecord / wodim Arguments

    /// Build cdrecord arguments for burning an audio CD.
    ///
    /// - Parameters:
    ///   - config: Burn configuration.
    ///   - wavFiles: WAV files in playback order.
    /// - Returns: Argument array for cdrecord.
    public static func buildAudioCDBurnArguments(
        config: BurnConfig,
        wavFiles: [String]
    ) -> [String] {
        var args: [String] = []

        args += ["dev=\(config.devicePath)"]
        args += ["speed=\(config.speed.cdrecordValue)"]

        if config.simulate {
            args.append("-dummy")
        }

        if config.ejectAfterBurn {
            args.append("-eject")
        }

        // Audio CD mode
        args.append("-audio")

        // Buffer underrun protection
        args.append("driveropts=burnfree")

        // Disc-at-once for gapless playback
        args.append("-dao")

        // Add WAV files
        args += wavFiles

        return args
    }

    /// Build cdrecord arguments for burning a data CD/DVD.
    ///
    /// - Parameters:
    ///   - config: Burn configuration.
    /// - Returns: Argument array for cdrecord.
    public static func buildDataDiscBurnArguments(
        config: BurnConfig
    ) -> [String] {
        var args: [String] = []

        args += ["dev=\(config.devicePath)"]
        args += ["speed=\(config.speed.cdrecordValue)"]

        if config.simulate {
            args.append("-dummy")
        }

        if config.ejectAfterBurn {
            args.append("-eject")
        }

        // Buffer underrun protection
        args.append("driveropts=burnfree")

        // Verify after burn
        if config.verify {
            args.append("-v")
        }

        // ISO image
        args.append(config.sourcePath)

        return args
    }

    // MARK: - Disc Blanking

    /// Build cdrecord arguments for blanking a rewritable disc.
    ///
    /// - Parameters:
    ///   - devicePath: Device path.
    ///   - blankType: Blank type ("fast", "all", "session", "track").
    /// - Returns: Argument array for cdrecord.
    public static func buildBlankArguments(
        devicePath: String,
        blankType: String = "fast"
    ) -> [String] {
        return [
            "dev=\(devicePath)",
            "blank=\(blankType)",
        ]
    }

    // MARK: - growisofs Arguments

    /// Build growisofs arguments for burning a DVD or Blu-ray.
    ///
    /// growisofs combines ISO creation and burning in one step.
    ///
    /// - Parameters:
    ///   - config: Burn configuration.
    /// - Returns: Argument array for growisofs.
    public static func buildGrowisofsArguments(
        config: BurnConfig
    ) -> [String] {
        var args: [String] = []

        if let speed = burnSpeedMultiplier(config.speed) {
            args += ["-speed=\(speed)"]
        }

        // DVD compatibility mode
        if config.format == .dvdVideo {
            args.append("-dvd-compat")
        }

        // Burn ISO
        args += ["-Z", "\(config.devicePath)=\(config.sourcePath)"]

        return args
    }

    // MARK: - Disc Eject

    /// Build eject command arguments.
    ///
    /// - Parameter devicePath: Device path.
    /// - Returns: Argument array for eject command.
    public static func buildEjectArguments(devicePath: String) -> [String] {
        return [devicePath]
    }

    /// Build disc tray close arguments.
    ///
    /// - Parameter devicePath: Device path.
    /// - Returns: Argument array for eject -t (close tray).
    public static func buildCloseTrayArguments(devicePath: String) -> [String] {
        return ["-t", devicePath]
    }

    // MARK: - macOS DRBurn

    /// Build hdiutil arguments to burn an ISO on macOS.
    ///
    /// macOS uses hdiutil as a high-level disc burning interface.
    ///
    /// - Parameters:
    ///   - isoPath: Path to the ISO image.
    ///   - verify: Whether to verify after burning.
    /// - Returns: Argument array for hdiutil.
    public static func buildHdiutilBurnArguments(
        isoPath: String,
        verify: Bool = true
    ) -> [String] {
        var args = ["burn", isoPath]

        if verify {
            args.append("-verifyburn")
        }

        args.append("-noverifydisc")

        return args
    }

    /// Build drutil arguments for disc operations on macOS.
    ///
    /// - Parameter action: Drutil action ("burn", "eject", "info", "tray open", "tray close").
    /// - Returns: Argument array for drutil.
    public static func buildDrutilArguments(action: String) -> [String] {
        return action.split(separator: " ").map(String.init)
    }

    // MARK: - Validation

    /// Validate a burn configuration.
    ///
    /// - Parameter config: Burn configuration to validate.
    /// - Returns: Array of error messages. Empty means valid.
    public static func validate(config: BurnConfig) -> [String] {
        var errors: [String] = []

        if config.devicePath.isEmpty {
            errors.append("Device path is required")
        }
        if config.sourcePath.isEmpty {
            errors.append("Source path is required")
        }

        return errors
    }

    // MARK: - Private

    private static func burnSpeedMultiplier(_ speed: BurnSpeed) -> Int? {
        switch speed {
        case .auto: return nil
        case .multiplier(let x): return x
        case .maximum: return nil
        }
    }
}
