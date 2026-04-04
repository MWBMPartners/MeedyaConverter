// ============================================================================
// MeedyaConverter — LinuxPlatform
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - LinuxDistro

/// Known Linux distributions for package management.
public enum LinuxDistro: String, Codable, Sendable, CaseIterable {
    case ubuntu = "ubuntu"
    case debian = "debian"
    case fedora = "fedora"
    case rhel = "rhel"
    case centos = "centos"
    case arch = "arch"
    case opensuse = "opensuse"
    case raspberryPiOS = "raspbian"
    case unknown = "unknown"

    /// Display name.
    public var displayName: String {
        switch self {
        case .ubuntu: return "Ubuntu"
        case .debian: return "Debian"
        case .fedora: return "Fedora"
        case .rhel: return "Red Hat Enterprise Linux"
        case .centos: return "CentOS"
        case .arch: return "Arch Linux"
        case .opensuse: return "openSUSE"
        case .raspberryPiOS: return "Raspberry Pi OS"
        case .unknown: return "Unknown Linux"
        }
    }

    /// Package manager command.
    public var packageManager: String {
        switch self {
        case .ubuntu, .debian, .raspberryPiOS:
            return "apt"
        case .fedora, .rhel, .centos:
            return "dnf"
        case .arch:
            return "pacman"
        case .opensuse:
            return "zypper"
        case .unknown:
            return "apt" // Fallback
        }
    }

    /// FFmpeg package name for this distro's package manager.
    public var ffmpegPackageName: String {
        switch self {
        case .ubuntu, .debian, .raspberryPiOS:
            return "ffmpeg"
        case .fedora:
            return "ffmpeg-free" // Fedora RPM Fusion for full ffmpeg
        case .rhel, .centos:
            return "ffmpeg" // Requires EPEL + RPM Fusion
        case .arch:
            return "ffmpeg"
        case .opensuse:
            return "ffmpeg-7" // Or ffmpeg-6 depending on version
        case .unknown:
            return "ffmpeg"
        }
    }

    /// Install command for FFmpeg.
    public var ffmpegInstallCommand: String {
        switch self {
        case .ubuntu, .debian, .raspberryPiOS:
            return "sudo apt install -y ffmpeg"
        case .fedora:
            return "sudo dnf install -y ffmpeg-free" // Or ffmpeg from RPM Fusion
        case .rhel, .centos:
            return "sudo dnf install -y ffmpeg"
        case .arch:
            return "sudo pacman -S --noconfirm ffmpeg"
        case .opensuse:
            return "sudo zypper install -y ffmpeg-7"
        case .unknown:
            return "# Install ffmpeg using your system package manager"
        }
    }
}

// MARK: - LinuxDesktopEnvironment

/// Known Linux desktop environments.
public enum LinuxDesktopEnvironment: String, Codable, Sendable {
    case gnome = "GNOME"
    case kde = "KDE"
    case xfce = "Xfce"
    case mate = "MATE"
    case cinnamon = "Cinnamon"
    case lxqt = "LXQt"
    case headless = "headless"
    case unknown = "unknown"

    /// Detect from environment variables.
    public static func detect() -> LinuxDesktopEnvironment {
        let desktop = ProcessInfo.processInfo.environment["XDG_CURRENT_DESKTOP"] ?? ""
        let lower = desktop.lowercased()

        if lower.contains("gnome") { return .gnome }
        if lower.contains("kde") || lower.contains("plasma") { return .kde }
        if lower.contains("xfce") { return .xfce }
        if lower.contains("mate") { return .mate }
        if lower.contains("cinnamon") { return .cinnamon }
        if lower.contains("lxqt") { return .lxqt }

        if ProcessInfo.processInfo.environment["DISPLAY"] == nil
            && ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] == nil {
            return .headless
        }

        return .unknown
    }
}

// MARK: - LinuxPackageFormat

/// Linux package distribution formats.
public enum LinuxPackageFormat: String, Codable, Sendable, CaseIterable {
    case deb = "deb"
    case rpm = "rpm"
    case appImage = "AppImage"
    case flatpak = "flatpak"
    case snap = "snap"
    case tarball = "tar.gz"

    /// Display name.
    public var displayName: String {
        switch self {
        case .deb: return "Debian Package (.deb)"
        case .rpm: return "RPM Package (.rpm)"
        case .appImage: return "AppImage"
        case .flatpak: return "Flatpak"
        case .snap: return "Snap"
        case .tarball: return "Tarball (.tar.gz)"
        }
    }

    /// Whether this format is sandboxed.
    public var isSandboxed: Bool {
        switch self {
        case .flatpak, .snap: return true
        default: return false
        }
    }

    /// Recommended format for a given distro.
    public static func recommended(for distro: LinuxDistro) -> LinuxPackageFormat {
        switch distro {
        case .ubuntu, .debian, .raspberryPiOS:
            return .deb
        case .fedora, .rhel, .centos, .opensuse:
            return .rpm
        case .arch:
            return .tarball // AUR uses PKGBUILD
        case .unknown:
            return .appImage // Most universal
        }
    }
}

// MARK: - LinuxPlatform

/// Linux-specific platform support for MeedyaConverter.
///
/// Provides:
/// - VAAPI hardware encoding setup with device detection
/// - V4L2 encoding for Raspberry Pi
/// - Linux distro detection
/// - Desktop entry file generation
/// - udev rules for optical disc access
/// - AppImage/Flatpak/Snap path handling
///
/// Phase 11
public struct LinuxPlatform: Sendable {

    // MARK: - VAAPI Hardware Encoding

    /// Build FFmpeg arguments for VAAPI hardware encoding on Linux.
    ///
    /// - Parameters:
    ///   - codec: Target codec (h264_vaapi, hevc_vaapi, av1_vaapi, vp9_vaapi).
    ///   - devicePath: VAAPI render device path (e.g., /dev/dri/renderD128).
    ///   - quality: Quality level (1-51, lower = better for qp mode).
    /// - Returns: FFmpeg argument array.
    public static func buildVAAPIEncodeArguments(
        codec: String,
        devicePath: String = "/dev/dri/renderD128",
        quality: Int = 23
    ) -> [String] {
        var args: [String] = []

        // Initialize VAAPI device
        args += ["-vaapi_device", devicePath]

        // Hardware upload filter
        args += ["-vf", "format=nv12,hwupload"]

        // Encoder
        args += ["-c:v", codec]
        args += ["-qp", "\(quality)"]

        return args
    }

    /// Build FFmpeg arguments for VAAPI hardware decoding on Linux.
    ///
    /// - Parameter devicePath: VAAPI render device path.
    /// - Returns: FFmpeg arguments for VAAPI decoding.
    public static func buildVAAPIDecodeArguments(
        devicePath: String = "/dev/dri/renderD128"
    ) -> [String] {
        return [
            "-hwaccel", "vaapi",
            "-hwaccel_device", devicePath,
            "-hwaccel_output_format", "vaapi",
        ]
    }

    /// Known VAAPI render device paths to check.
    public static let vaapiDevicePaths: [String] = [
        "/dev/dri/renderD128",
        "/dev/dri/renderD129",
        "/dev/dri/renderD130",
    ]

    /// Build vainfo arguments to query VAAPI capabilities.
    ///
    /// - Parameter devicePath: VAAPI render device path.
    /// - Returns: Argument array for vainfo.
    public static func buildVainfoArguments(devicePath: String) -> [String] {
        return ["--display", "drm", "--device", devicePath]
    }

    // MARK: - V4L2 (Raspberry Pi)

    /// Build FFmpeg arguments for V4L2 hardware encoding on Raspberry Pi.
    ///
    /// - Parameters:
    ///   - codec: Target codec (h264_v4l2m2m).
    ///   - bitrate: Target bitrate in kbps.
    /// - Returns: FFmpeg argument array.
    public static func buildV4L2EncodeArguments(
        codec: String = "h264_v4l2m2m",
        bitrate: Int = 5000
    ) -> [String] {
        return [
            "-c:v", codec,
            "-b:v", "\(bitrate)k",
        ]
    }

    /// Known V4L2 device paths.
    public static let v4l2DevicePaths: [String] = [
        "/dev/video10",  // RPi encoder
        "/dev/video11",  // RPi decoder
        "/dev/video12",  // Additional
    ]

    /// Raspberry Pi memory-conscious encoding settings.
    ///
    /// RPi has limited RAM (2-8 GB), so encoding settings need adjustment.
    ///
    /// - Parameter availableRAM_MB: Available RAM in megabytes.
    /// - Returns: FFmpeg thread and buffer arguments.
    public static func buildRPiEncodingArgs(availableRAM_MB: Int) -> [String] {
        var args: [String] = []

        // Limit threads based on available RAM
        let threads: Int
        if availableRAM_MB < 2048 {
            threads = 2
        } else if availableRAM_MB < 4096 {
            threads = 3
        } else {
            threads = 4
        }
        args += ["-threads", "\(threads)"]

        // Smaller lookahead buffer
        if availableRAM_MB < 4096 {
            args += ["-rc-lookahead", "10"]
        }

        return args
    }

    // MARK: - Distro Detection

    /// Parse /etc/os-release to detect the Linux distribution.
    ///
    /// - Parameter osReleasePath: Path to os-release file.
    /// - Returns: Detected distribution.
    public static func detectDistro(
        osReleasePath: String = "/etc/os-release"
    ) -> LinuxDistro {
        guard let content = try? String(contentsOfFile: osReleasePath, encoding: .utf8) else {
            return .unknown
        }

        let id = parseOSReleaseField(content: content, field: "ID")?.lowercased() ?? ""

        switch id {
        case "ubuntu": return .ubuntu
        case "debian": return .debian
        case "fedora": return .fedora
        case "rhel": return .rhel
        case "centos": return .centos
        case "arch": return .arch
        case "opensuse-leap", "opensuse-tumbleweed", "opensuse": return .opensuse
        case "raspbian": return .raspberryPiOS
        default:
            // Check ID_LIKE for derivatives
            let idLike = parseOSReleaseField(content: content, field: "ID_LIKE")?.lowercased() ?? ""
            if idLike.contains("ubuntu") || idLike.contains("debian") { return .debian }
            if idLike.contains("fedora") || idLike.contains("rhel") { return .fedora }
            return .unknown
        }
    }

    /// Parse a field from os-release file content.
    private static func parseOSReleaseField(content: String, field: String) -> String? {
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, String(parts[0]) == field else { continue }
            return String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    // MARK: - Desktop Entry

    /// Generate a .desktop entry file for Linux application menus.
    ///
    /// - Parameters:
    ///   - execPath: Path to the executable.
    ///   - iconPath: Path to the application icon.
    /// - Returns: Desktop entry file content.
    public static func generateDesktopEntry(
        execPath: String,
        iconPath: String
    ) -> String {
        return """
        [Desktop Entry]
        Type=Application
        Name=MeedyaConverter
        GenericName=Media Converter
        Comment=Convert, encode, and process media files
        Exec=\(execPath) %F
        Icon=\(iconPath)
        Terminal=false
        Categories=AudioVideo;Audio;Video;
        MimeType=video/mp4;video/x-matroska;video/webm;video/quicktime;audio/mpeg;audio/flac;audio/ogg;
        StartupNotify=true
        Keywords=video;audio;convert;encode;transcode;ffmpeg;
        """
    }

    // MARK: - udev Rules

    /// Generate udev rules for non-root optical disc access.
    ///
    /// Allows users in the 'cdrom' group to access optical drives without sudo.
    ///
    /// - Returns: udev rule content.
    public static func generateOpticalDiscUdevRules() -> String {
        return """
        # MeedyaConverter — Optical disc drive access rules
        # Install to: /etc/udev/rules.d/99-meedyaconverter-optical.rules
        # Then run: sudo udevadm control --reload-rules

        # CD/DVD/Blu-ray drives — grant group 'cdrom' read/write access
        SUBSYSTEM=="block", KERNEL=="sr[0-9]*", GROUP="cdrom", MODE="0660"
        SUBSYSTEM=="block", KERNEL=="sg[0-9]*", GROUP="cdrom", MODE="0660"

        # SG (SCSI Generic) devices for direct disc access
        SUBSYSTEM=="scsi_generic", GROUP="cdrom", MODE="0660"
        """
    }

    /// Linux optical drive device paths to check.
    public static let opticalDriveDevices: [String] = [
        "/dev/sr0",
        "/dev/sr1",
        "/dev/cdrom",
        "/dev/dvd",
    ]

    /// Build udevadm arguments to query drive capabilities.
    ///
    /// - Parameter devicePath: Device path (e.g., /dev/sr0).
    /// - Returns: Argument array for udevadm.
    public static func buildUdevadmInfoArguments(devicePath: String) -> [String] {
        return ["info", "--query=property", "--name=\(devicePath)"]
    }

    // MARK: - Flatpak / Snap

    /// Flatpak permissions required for MeedyaConverter.
    public static let flatpakPermissions: [String] = [
        "--filesystem=home",               // Read/write user files
        "--filesystem=/tmp",               // Temp directory for encoding
        "--device=all",                    // Optical drive access
        "--share=network",                 // Network for metadata lookup
        "--socket=wayland",                // Wayland display
        "--socket=fallback-x11",           // X11 fallback
        "--socket=pulseaudio",             // Audio playback
    ]

    /// Snap plugs required for MeedyaConverter.
    public static let snapPlugs: [String] = [
        "home",                            // Home directory access
        "removable-media",                 // USB/optical drive access
        "raw-usb",                         // Direct disc access
        "network",                         // Network for metadata lookup
        "desktop",                         // Desktop integration
        "audio-playback",                  // Audio playback
        "opengl",                          // GPU acceleration
    ]

    // MARK: - AppImage

    /// Generate AppRun script for AppImage packaging.
    ///
    /// - Returns: AppRun script content.
    public static func generateAppRunScript() -> String {
        return """
        #!/bin/bash
        SELF=$(readlink -f "$0")
        HERE=${SELF%/*}
        export PATH="${HERE}/usr/bin:${PATH}"
        export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
        exec "${HERE}/usr/bin/meedya-convert" "$@"
        """
    }

    // MARK: - Package Dependencies

    /// System package dependencies for building on Debian/Ubuntu.
    public static let debianBuildDependencies: [String] = [
        "swift",
        "libgtk-4-dev",
        "libadwaita-1-dev",
        "ffmpeg",
        "libavcodec-dev",
        "libavformat-dev",
        "libswscale-dev",
        "libcdio-dev",
        "libdvdread-dev",
        "libbluray-dev",
        "libva-dev",
    ]

    /// System package dependencies for building on Fedora.
    public static let fedoraBuildDependencies: [String] = [
        "swift-lang",
        "gtk4-devel",
        "libadwaita-devel",
        "ffmpeg-free-devel",
        "libcdio-devel",
        "libdvdread-devel",
        "libbluray-devel",
        "libva-devel",
    ]
}
