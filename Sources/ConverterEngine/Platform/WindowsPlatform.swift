// ============================================================================
// MeedyaConverter — WindowsPlatform
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - WindowsInstallConfig

/// Configuration for Windows MSI/MSIX installer generation.
public struct WindowsInstallConfig: Codable, Sendable {
    /// Application name.
    public var appName: String

    /// Application version.
    public var version: String

    /// Manufacturer name.
    public var manufacturer: String

    /// Installation directory (relative to Program Files).
    public var installDir: String

    /// Whether to create a Start Menu shortcut.
    public var startMenuShortcut: Bool

    /// Whether to create a desktop shortcut.
    public var desktopShortcut: Bool

    /// Whether to register file type associations.
    public var fileAssociations: Bool

    /// Whether to add to system PATH.
    public var addToPath: Bool

    /// Installer type.
    public var installerType: WindowsInstallerType

    public init(
        appName: String = "MeedyaConverter",
        version: String = "1.0.0",
        manufacturer: String = "MWBM Partners Ltd",
        installDir: String = "MeedyaConverter",
        startMenuShortcut: Bool = true,
        desktopShortcut: Bool = false,
        fileAssociations: Bool = true,
        addToPath: Bool = true,
        installerType: WindowsInstallerType = .msix
    ) {
        self.appName = appName
        self.version = version
        self.manufacturer = manufacturer
        self.installDir = installDir
        self.startMenuShortcut = startMenuShortcut
        self.desktopShortcut = desktopShortcut
        self.fileAssociations = fileAssociations
        self.addToPath = addToPath
        self.installerType = installerType
    }
}

// MARK: - WindowsInstallerType

/// Windows installer package types.
public enum WindowsInstallerType: String, Codable, Sendable {
    case msi = "msi"
    case msix = "msix"
    case exe = "exe"

    /// Display name.
    public var displayName: String {
        switch self {
        case .msi: return "Windows Installer (MSI)"
        case .msix: return "MSIX Package"
        case .exe: return "Setup Executable"
        }
    }
}

// MARK: - WindowsDriveInfo

/// Information about a Windows drive letter mapping to an optical drive.
public struct WindowsDriveInfo: Codable, Sendable {
    /// Drive letter (e.g., "D", "E").
    public var driveLetter: String

    /// Volume label.
    public var volumeLabel: String?

    /// Drive type description.
    public var driveType: WindowsDriveType

    /// Whether the drive is ready (has media inserted).
    public var isReady: Bool

    public init(
        driveLetter: String,
        volumeLabel: String? = nil,
        driveType: WindowsDriveType = .cdrom,
        isReady: Bool = false
    ) {
        self.driveLetter = driveLetter
        self.volumeLabel = volumeLabel
        self.driveType = driveType
        self.isReady = isReady
    }

    /// Device path for Windows disc access.
    public var devicePath: String {
        return "\\\\.\\\\\\(driveLetter):"
    }
}

// MARK: - WindowsDriveType

/// Windows drive type enumeration (from GetDriveType API).
public enum WindowsDriveType: Int, Codable, Sendable {
    case unknown = 0
    case noRootDir = 1
    case removable = 2
    case fixed = 3
    case remote = 4
    case cdrom = 5
    case ramDisk = 6

    /// Display name.
    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .noRootDir: return "No Root Directory"
        case .removable: return "Removable"
        case .fixed: return "Fixed"
        case .remote: return "Network"
        case .cdrom: return "CD-ROM / Optical"
        case .ramDisk: return "RAM Disk"
        }
    }

    /// Whether this is an optical drive.
    public var isOptical: Bool {
        self == .cdrom
    }
}

// MARK: - WindowsPlatform

/// Windows-specific platform support for MeedyaConverter.
///
/// Provides:
/// - IMAPI v2 disc burning argument helpers
/// - Windows drive detection helpers
/// - Windows installer path conventions
/// - Hardware encoding setup (NVENC, QSV, AMF)
/// - DXVA2/D3D11VA hardware decoding helpers
///
/// Phase 10
public struct WindowsPlatform: Sendable {

    // MARK: - FFmpeg Paths

    /// Default FFmpeg installation directory on Windows.
    public static var defaultFFmpegDir: String {
        let programFiles = ProcessInfo.processInfo.environment["ProgramFiles"]
            ?? "C:\\Program Files"
        return "\(programFiles)\\MeedyaConverter\\tools"
    }

    /// Build the expected FFmpeg binary path.
    public static func ffmpegPath(in directory: String) -> String {
        return (directory as NSString).appendingPathComponent("ffmpeg.exe")
    }

    /// Build the expected FFprobe binary path.
    public static func ffprobePath(in directory: String) -> String {
        return (directory as NSString).appendingPathComponent("ffprobe.exe")
    }

    // MARK: - Hardware Encoding

    /// Build FFmpeg arguments for NVENC hardware encoding on Windows.
    ///
    /// - Parameters:
    ///   - codec: Target codec (.h264, .h265, .av1).
    ///   - preset: NVENC preset (p1=fastest to p7=slowest/best quality).
    ///   - cq: Constant quality value (0-51, lower=better).
    ///   - gpuIndex: GPU index for multi-GPU systems (nil=default).
    /// - Returns: FFmpeg argument array.
    public static func buildNVENCArguments(
        codec: String,
        preset: String = "p5",
        cq: Int = 23,
        gpuIndex: Int? = nil
    ) -> [String] {
        var args: [String] = []

        if let gpu = gpuIndex {
            args += ["-gpu", "\(gpu)"]
        }

        args += ["-c:v", codec]
        args += ["-preset", preset]
        args += ["-tune", "hq"]
        args += ["-rc", "vbr"]
        args += ["-cq", "\(cq)"]
        args += ["-b:v", "0"]

        return args
    }

    /// Build FFmpeg arguments for Intel QSV hardware encoding on Windows.
    ///
    /// - Parameters:
    ///   - codec: Target codec (h264_qsv, hevc_qsv, av1_qsv).
    ///   - preset: QSV preset (veryfast to veryslow).
    ///   - globalQuality: Quality parameter (1-51, lower=better).
    /// - Returns: FFmpeg argument array.
    public static func buildQSVArguments(
        codec: String,
        preset: String = "medium",
        globalQuality: Int = 23
    ) -> [String] {
        var args: [String] = []

        // QSV initialization on Windows
        args += ["-init_hw_device", "qsv=qsv:MFX_IMPL_hw"]
        args += ["-filter_hw_device", "qsv"]

        args += ["-c:v", codec]
        args += ["-preset", preset]
        args += ["-global_quality", "\(globalQuality)"]

        return args
    }

    /// Build FFmpeg arguments for AMD AMF hardware encoding on Windows.
    ///
    /// - Parameters:
    ///   - codec: Target codec (h264_amf, hevc_amf, av1_amf).
    ///   - quality: Quality preset (speed, balanced, quality).
    ///   - cq: Constant quality level.
    /// - Returns: FFmpeg argument array.
    public static func buildAMFArguments(
        codec: String,
        quality: String = "balanced",
        cq: Int = 23
    ) -> [String] {
        var args: [String] = []

        args += ["-c:v", codec]
        args += ["-quality", quality]
        args += ["-rc", "cqp"]
        args += ["-qp_i", "\(cq)"]
        args += ["-qp_p", "\(cq)"]

        return args
    }

    // MARK: - Hardware Decoding

    /// Build FFmpeg arguments for D3D11VA hardware decoding on Windows.
    ///
    /// - Returns: FFmpeg arguments to enable D3D11VA decoding.
    public static func buildD3D11VADecodeArguments() -> [String] {
        return ["-hwaccel", "d3d11va", "-hwaccel_output_format", "d3d11"]
    }

    /// Build FFmpeg arguments for DXVA2 hardware decoding on Windows.
    ///
    /// - Returns: FFmpeg arguments to enable DXVA2 decoding.
    public static func buildDXVA2DecodeArguments() -> [String] {
        return ["-hwaccel", "dxva2"]
    }

    // MARK: - IMAPI Disc Burning

    /// Build PowerShell commands for disc burning via IMAPI v2.
    ///
    /// IMAPI (Image Mastering API) is the native Windows disc burning API.
    ///
    /// - Parameters:
    ///   - isoPath: Path to the ISO image.
    ///   - driveLetter: Drive letter of the disc writer.
    ///   - speed: Burn speed (nil = default).
    /// - Returns: PowerShell script content.
    public static func buildIMAPIBurnScript(
        isoPath: String,
        driveLetter: String,
        speed: Int? = nil
    ) -> String {
        var script = """
        # IMAPI v2 Disc Burning Script
        $discMaster = New-Object -ComObject IMAPI2.MsftDiscMaster2
        $recorder = New-Object -ComObject IMAPI2.MsftDiscRecorder2
        $recorder.InitializeDiscRecorder($discMaster.Item(0))

        $burnImage = New-Object -ComObject IMAPI2.MsftDiscFormat2Data
        $burnImage.Recorder = $recorder
        $burnImage.ClientName = "MeedyaConverter"

        """

        if let s = speed {
            script += "$burnImage.SetWriteSpeed(\(s), $true)\n"
        }

        script += """

        $stream = New-Object -ComObject ADODB.Stream
        $stream.Open()
        $stream.Type = 1  # Binary
        $stream.LoadFromFile("\(isoPath)")

        $burnImage.Write($stream)
        $stream.Close()
        $recorder.EjectMedia()
        """

        return script
    }

    // MARK: - File Associations

    /// Media file extensions to register on Windows.
    public static let mediaFileExtensions: [String: String] = [
        ".mp4": "video/mp4",
        ".mkv": "video/x-matroska",
        ".avi": "video/x-msvideo",
        ".mov": "video/quicktime",
        ".webm": "video/webm",
        ".m4v": "video/mp4",
        ".ts": "video/mp2t",
        ".flv": "video/x-flv",
        ".mp3": "audio/mpeg",
        ".flac": "audio/flac",
        ".aac": "audio/aac",
        ".m4a": "audio/mp4",
        ".wav": "audio/wav",
        ".ogg": "audio/ogg",
        ".opus": "audio/opus",
        ".srt": "text/plain",
        ".vtt": "text/vtt",
        ".ass": "text/plain",
    ]

    // MARK: - WiX Installer

    /// Generate a WiX component entry for the installer.
    ///
    /// - Parameters:
    ///   - filePath: Path to the file to include.
    ///   - componentId: Unique component GUID.
    /// - Returns: WiX XML fragment.
    public static func generateWiXComponent(
        filePath: String,
        componentId: String
    ) -> String {
        let filename = (filePath as NSString).lastPathComponent
        return """
        <Component Id="\(componentId)" Guid="*">
          <File Id="\(componentId)_File" Source="\(filePath)" Name="\(filename)" />
        </Component>
        """
    }

    // MARK: - Taskbar Progress

    /// Windows taskbar progress states (ITaskbarList3).
    public enum TaskbarProgressState: Int, Sendable {
        case noProgress = 0
        case indeterminate = 1
        case normal = 2
        case error = 4
        case paused = 8
    }
}
