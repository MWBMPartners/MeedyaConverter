// ============================================================================
// MeedyaConverter — PlatformSupport
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - Platform

/// The operating system platform the app is running on.
public enum Platform: String, Codable, Sendable, CaseIterable {
    case macOS = "macos"
    case windows = "windows"
    case linux = "linux"

    /// Display name.
    public var displayName: String {
        switch self {
        case .macOS: return "macOS"
        case .windows: return "Windows"
        case .linux: return "Linux"
        }
    }

    /// The current platform at compile time.
    public static var current: Platform {
        #if os(macOS) || os(iOS)
        return .macOS
        #elseif os(Windows)
        return .windows
        #elseif os(Linux)
        return .linux
        #else
        return .linux // Default fallback
        #endif
    }
}

// MARK: - Architecture

/// CPU architecture.
public enum Architecture: String, Codable, Sendable, CaseIterable {
    case x86_64 = "x86_64"
    case arm64 = "arm64"
    case armv7 = "armv7"
    case universal = "universal"

    /// Display name.
    public var displayName: String {
        switch self {
        case .x86_64: return "x86-64 (Intel/AMD)"
        case .arm64: return "ARM64 (Apple Silicon / ARM)"
        case .armv7: return "ARMv7 (32-bit ARM)"
        case .universal: return "Universal (Multi-Architecture)"
        }
    }

    /// The current architecture at compile time.
    public static var current: Architecture {
        #if arch(x86_64)
        return .x86_64
        #elseif arch(arm64)
        return .arm64
        #elseif arch(arm)
        return .armv7
        #else
        return .x86_64
        #endif
    }
}

// MARK: - PlatformPaths

/// Platform-specific file path conventions and search locations.
public struct PlatformPaths: Sendable {

    /// The FFmpeg binary name for the current platform.
    public static var ffmpegBinaryName: String {
        #if os(Windows)
        return "ffmpeg.exe"
        #else
        return "ffmpeg"
        #endif
    }

    /// The FFprobe binary name for the current platform.
    public static var ffprobeBinaryName: String {
        #if os(Windows)
        return "ffprobe.exe"
        #else
        return "ffprobe"
        #endif
    }

    /// PATH environment variable separator.
    public static var pathSeparator: String {
        #if os(Windows)
        return ";"
        #else
        return ":"
        #endif
    }

    /// File path separator.
    public static var fileSeparator: String {
        #if os(Windows)
        return "\\"
        #else
        return "/"
        #endif
    }

    /// Ordered search paths for FFmpeg binary discovery.
    ///
    /// Platform-specific paths are returned in priority order:
    /// - macOS: Homebrew (ARM, Intel), MacPorts, system
    /// - Windows: Program Files, Scoop, Chocolatey, WinGet
    /// - Linux: system paths, Snap, Flatpak, Homebrew for Linux
    public static var ffmpegSearchPaths: [String] {
        switch Platform.current {
        case .macOS:
            return [
                "/opt/homebrew/bin",        // Homebrew ARM (Apple Silicon)
                "/usr/local/bin",           // Homebrew Intel
                "/opt/local/bin",           // MacPorts
                "/usr/bin",
                "/bin",
            ]
        case .windows:
            return windowsFFmpegSearchPaths
        case .linux:
            return linuxFFmpegSearchPaths
        }
    }

    /// Windows-specific FFmpeg search paths.
    public static var windowsFFmpegSearchPaths: [String] {
        var paths: [String] = []

        // Program Files installations
        let programFiles = windowsEnvironment("ProgramFiles") ?? "C:\\Program Files"
        let programFilesX86 = windowsEnvironment("ProgramFiles(x86)") ?? "C:\\Program Files (x86)"
        let localAppData = windowsEnvironment("LOCALAPPDATA") ?? ""
        let userProfile = windowsEnvironment("USERPROFILE") ?? ""

        paths.append("\(programFiles)\\MeedyaConverter\\tools")
        paths.append("\(programFiles)\\FFmpeg\\bin")
        paths.append("\(programFilesX86)\\FFmpeg\\bin")

        // Scoop (per-user package manager)
        if !userProfile.isEmpty {
            paths.append("\(userProfile)\\scoop\\shims")
            paths.append("\(userProfile)\\scoop\\apps\\ffmpeg\\current\\bin")
        }

        // Chocolatey
        let chocoInstall = windowsEnvironment("ChocolateyInstall") ?? "C:\\ProgramData\\chocolatey"
        paths.append("\(chocoInstall)\\bin")

        // WinGet / Microsoft Store app paths
        if !localAppData.isEmpty {
            paths.append("\(localAppData)\\Microsoft\\WinGet\\Packages")
        }

        // Common manual install locations
        paths.append("C:\\FFmpeg\\bin")
        paths.append("C:\\tools\\ffmpeg\\bin")

        return paths
    }

    /// Linux-specific FFmpeg search paths.
    public static var linuxFFmpegSearchPaths: [String] {
        var paths: [String] = []

        // Standard Linux paths
        paths.append("/usr/bin")
        paths.append("/usr/local/bin")
        paths.append("/bin")

        // Snap
        paths.append("/snap/bin")

        // Flatpak
        paths.append("/var/lib/flatpak/exports/bin")

        // Homebrew for Linux (Linuxbrew)
        paths.append("/home/linuxbrew/.linuxbrew/bin")

        // AppImage extracted
        let home = linuxEnvironment("HOME") ?? ""
        if !home.isEmpty {
            paths.append("\(home)/.local/bin")
            paths.append("\(home)/bin")
        }

        return paths
    }

    /// Default application data directory.
    public static var applicationDataDirectory: String {
        switch Platform.current {
        case .macOS:
            return "~/Library/Application Support/MeedyaConverter"
        case .windows:
            let appData = windowsEnvironment("APPDATA") ?? "C:\\Users\\Default\\AppData\\Roaming"
            return "\(appData)\\MeedyaConverter"
        case .linux:
            let xdgData = linuxEnvironment("XDG_DATA_HOME")
                ?? "\(linuxEnvironment("HOME") ?? "~")/.local/share"
            return "\(xdgData)/MeedyaConverter"
        }
    }

    /// Default configuration directory.
    public static var configDirectory: String {
        switch Platform.current {
        case .macOS:
            return "~/Library/Preferences/MeedyaConverter"
        case .windows:
            let appData = windowsEnvironment("APPDATA") ?? "C:\\Users\\Default\\AppData\\Roaming"
            return "\(appData)\\MeedyaConverter\\config"
        case .linux:
            let xdgConfig = linuxEnvironment("XDG_CONFIG_HOME")
                ?? "\(linuxEnvironment("HOME") ?? "~")/.config"
            return "\(xdgConfig)/MeedyaConverter"
        }
    }

    /// Default cache directory.
    public static var cacheDirectory: String {
        switch Platform.current {
        case .macOS:
            return "~/Library/Caches/MeedyaConverter"
        case .windows:
            let localAppData = windowsEnvironment("LOCALAPPDATA") ?? "C:\\Users\\Default\\AppData\\Local"
            return "\(localAppData)\\MeedyaConverter\\cache"
        case .linux:
            let xdgCache = linuxEnvironment("XDG_CACHE_HOME")
                ?? "\(linuxEnvironment("HOME") ?? "~")/.cache"
            return "\(xdgCache)/MeedyaConverter"
        }
    }

    /// Default log directory.
    public static var logDirectory: String {
        switch Platform.current {
        case .macOS:
            return "~/Library/Logs/MeedyaConverter"
        case .windows:
            let localAppData = windowsEnvironment("LOCALAPPDATA") ?? "C:\\Users\\Default\\AppData\\Local"
            return "\(localAppData)\\MeedyaConverter\\logs"
        case .linux:
            let xdgState = linuxEnvironment("XDG_STATE_HOME")
                ?? "\(linuxEnvironment("HOME") ?? "~")/.local/state"
            return "\(xdgState)/MeedyaConverter/logs"
        }
    }

    /// Default temporary directory for encoding output.
    public static var tempDirectory: String {
        return NSTemporaryDirectory()
    }

    // MARK: - Private

    private static func windowsEnvironment(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    private static func linuxEnvironment(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}

// MARK: - PlatformCapabilities

/// Describes capabilities available on the current platform.
public struct PlatformCapabilities: Sendable {

    /// Hardware APIs available on this platform.
    public static var availableHardwareAPIs: [HardwareAPI] {
        switch Platform.current {
        case .macOS:
            return [.videoToolbox, .qsv] // Intel Macs may have QSV
        case .windows:
            return [.nvenc, .qsv, .amf]
        case .linux:
            return [.vaapi, .nvenc, .qsv]
        }
    }

    /// Whether the platform supports a native GUI framework.
    public static var hasNativeGUI: Bool {
        return true // All three platforms have GUI support
    }

    /// The native UI framework name for this platform.
    public static var nativeUIFramework: String {
        switch Platform.current {
        case .macOS: return "SwiftUI"
        case .windows: return "WinUI 3"
        case .linux: return "GTK4"
        }
    }

    /// Whether the platform supports optical disc operations.
    public static var supportsOpticalDisc: Bool {
        return true // All desktop platforms can support optical drives
    }

    /// The native disc burning framework (if any).
    public static var nativeDiscFramework: String? {
        switch Platform.current {
        case .macOS: return "DRBurn (DiscRecording.framework)"
        case .windows: return "IMAPI v2"
        case .linux: return nil // Uses cdrecord/wodim/growisofs
        }
    }

    /// Package manager names available on this platform.
    public static var packageManagers: [String] {
        switch Platform.current {
        case .macOS: return ["Homebrew", "MacPorts"]
        case .windows: return ["Scoop", "Chocolatey", "WinGet"]
        case .linux: return ["apt", "dnf", "pacman", "snap", "flatpak"]
        }
    }
}
