// ============================================================================
// MeedyaConverter — ConverterEngine unit tests
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Split from ConverterEngineTests.swift (re #452) to keep the test file
// under a manageable size. This file extends `ConverterEngineTests`
// (declared in ConverterEngineTests.swift) with a cohesive group of test
// methods. No test body, name, or assertion was changed during the split.
// ============================================================================

import XCTest
import ConverterEngine

extension ConverterEngineTests {
    // =========================================================================
    // MARK: - Phase 10-11: Platform Support
    // =========================================================================

    /// Verifies Platform enum.
    func test_platform_enum() {
        XCTAssertEqual(Platform.macOS.displayName, "macOS")
        XCTAssertEqual(Platform.windows.displayName, "Windows")
        XCTAssertEqual(Platform.linux.displayName, "Linux")

        // Current platform should be one of the cases
        let current = Platform.current
        XCTAssertTrue(Platform.allCases.contains(current))
    }

    /// Verifies Architecture enum.
    func test_architecture_enum() {
        XCTAssertEqual(Architecture.arm64.displayName, "ARM64 (Apple Silicon / ARM)")
        XCTAssertEqual(Architecture.x86_64.displayName, "x86-64 (Intel/AMD)")

        let current = Architecture.current
        XCTAssertTrue(Architecture.allCases.contains(current))
    }

    /// Verifies PlatformPaths binary names.
    func test_platformPaths_binaryNames() {
        // On current platform (macOS in dev), these should not be .exe
        #if os(Windows)
        XCTAssertTrue(PlatformPaths.ffmpegBinaryName.hasSuffix(".exe"))
        XCTAssertTrue(PlatformPaths.ffprobeBinaryName.hasSuffix(".exe"))
        XCTAssertEqual(PlatformPaths.pathSeparator, ";")
        #else
        XCTAssertEqual(PlatformPaths.ffmpegBinaryName, "ffmpeg")
        XCTAssertEqual(PlatformPaths.ffprobeBinaryName, "ffprobe")
        XCTAssertEqual(PlatformPaths.pathSeparator, ":")
        XCTAssertEqual(PlatformPaths.fileSeparator, "/")
        #endif
    }

    /// Verifies FFmpeg search paths are non-empty.
    func test_platformPaths_searchPaths() {
        let paths = PlatformPaths.ffmpegSearchPaths
        XCTAssertFalse(paths.isEmpty)
    }

    /// Verifies Windows-specific search paths contain expected locations.
    func test_platformPaths_windowsSearchPaths() {
        let paths = PlatformPaths.windowsFFmpegSearchPaths
        XCTAssertFalse(paths.isEmpty)
        // Should contain common Windows FFmpeg locations
        XCTAssertTrue(paths.contains { $0.contains("FFmpeg") || $0.contains("MeedyaConverter") })
    }

    /// Verifies Linux-specific search paths contain expected locations.
    func test_platformPaths_linuxSearchPaths() {
        let paths = PlatformPaths.linuxFFmpegSearchPaths
        XCTAssertFalse(paths.isEmpty)
        XCTAssertTrue(paths.contains("/usr/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
        XCTAssertTrue(paths.contains("/snap/bin"))
    }

    /// Verifies application data directories are non-empty.
    func test_platformPaths_directories() {
        XCTAssertFalse(PlatformPaths.applicationDataDirectory.isEmpty)
        XCTAssertFalse(PlatformPaths.configDirectory.isEmpty)
        XCTAssertFalse(PlatformPaths.cacheDirectory.isEmpty)
        XCTAssertFalse(PlatformPaths.logDirectory.isEmpty)
        XCTAssertFalse(PlatformPaths.tempDirectory.isEmpty)
    }

    /// Verifies PlatformCapabilities.
    func test_platformCapabilities() {
        let apis = PlatformCapabilities.availableHardwareAPIs
        XCTAssertFalse(apis.isEmpty)

        XCTAssertTrue(PlatformCapabilities.hasNativeGUI)
        XCTAssertFalse(PlatformCapabilities.nativeUIFramework.isEmpty)
        XCTAssertTrue(PlatformCapabilities.supportsOpticalDisc)
        XCTAssertFalse(PlatformCapabilities.packageManagers.isEmpty)
    }

    // =========================================================================
    // MARK: - Phase 10: Windows Platform
    // =========================================================================

    /// Verifies WindowsInstallerType properties.
    func test_windowsInstallerType() {
        XCTAssertEqual(WindowsInstallerType.msi.displayName, "Windows Installer (MSI)")
        XCTAssertEqual(WindowsInstallerType.msix.displayName, "MSIX Package")
    }

    /// Verifies WindowsDriveInfo device path construction.
    func test_windowsDriveInfo_devicePath() {
        let drive = WindowsDriveInfo(driveLetter: "D", driveType: .cdrom, isReady: true)
        XCTAssertFalse(drive.devicePath.isEmpty)
        XCTAssertTrue(drive.driveType.isOptical)
    }

    /// Verifies WindowsDriveType properties.
    func test_windowsDriveType() {
        XCTAssertTrue(WindowsDriveType.cdrom.isOptical)
        XCTAssertFalse(WindowsDriveType.fixed.isOptical)
        XCTAssertFalse(WindowsDriveType.removable.isOptical)
        XCTAssertEqual(WindowsDriveType.cdrom.displayName, "CD-ROM / Optical")
    }

    /// Verifies NVENC argument builder.
    func test_windowsPlatform_nvencArguments() {
        let args = WindowsPlatform.buildNVENCArguments(
            codec: "h264_nvenc",
            preset: "p7",
            cq: 20,
            gpuIndex: 0
        )
        XCTAssertTrue(args.contains("h264_nvenc"))
        XCTAssertTrue(args.contains("p7"))
        XCTAssertTrue(args.contains("20"))
        XCTAssertTrue(args.contains("-gpu"))
        XCTAssertTrue(args.contains("hq"))
        XCTAssertTrue(args.contains("vbr"))
    }

    /// Verifies QSV argument builder.
    func test_windowsPlatform_qsvArguments() {
        let args = WindowsPlatform.buildQSVArguments(
            codec: "hevc_qsv",
            preset: "veryslow",
            globalQuality: 18
        )
        XCTAssertTrue(args.contains("hevc_qsv"))
        XCTAssertTrue(args.contains("-init_hw_device"))
        XCTAssertTrue(args.contains("-global_quality"))
        XCTAssertTrue(args.contains("18"))
    }

    /// Verifies AMF argument builder.
    func test_windowsPlatform_amfArguments() {
        let args = WindowsPlatform.buildAMFArguments(
            codec: "hevc_amf",
            quality: "quality",
            cq: 20
        )
        XCTAssertTrue(args.contains("hevc_amf"))
        XCTAssertTrue(args.contains("quality"))
        XCTAssertTrue(args.contains("cqp"))
    }

    /// Verifies D3D11VA decode arguments.
    func test_windowsPlatform_d3d11vaArguments() {
        let args = WindowsPlatform.buildD3D11VADecodeArguments()
        XCTAssertTrue(args.contains("d3d11va"))
        XCTAssertTrue(args.contains("d3d11"))
    }

    /// Verifies DXVA2 decode arguments.
    func test_windowsPlatform_dxva2Arguments() {
        let args = WindowsPlatform.buildDXVA2DecodeArguments()
        XCTAssertTrue(args.contains("dxva2"))
    }

    /// Verifies IMAPI burn script generation.
    func test_windowsPlatform_imapiBurnScript() {
        let script = WindowsPlatform.buildIMAPIBurnScript(
            isoPath: "C:\\temp\\movie.iso",
            driveLetter: "D",
            speed: 8
        )
        XCTAssertTrue(script.contains("IMAPI2"))
        XCTAssertTrue(script.contains("movie.iso"))
        XCTAssertTrue(script.contains("MeedyaConverter"))
    }

    /// Verifies WiX component generation.
    func test_windowsPlatform_wixComponent() {
        let xml = WindowsPlatform.generateWiXComponent(
            filePath: "C:\\build\\ffmpeg.exe",
            componentId: "FFmpegExe"
        )
        XCTAssertTrue(xml.contains("<Component"))
        XCTAssertTrue(xml.contains("FFmpegExe"))
        XCTAssertTrue(xml.contains("ffmpeg.exe"))
    }

    /// Verifies media file extensions are populated.
    func test_windowsPlatform_fileAssociations() {
        XCTAssertFalse(WindowsPlatform.mediaFileExtensions.isEmpty)
        XCTAssertEqual(WindowsPlatform.mediaFileExtensions[".mp4"], "video/mp4")
        XCTAssertEqual(WindowsPlatform.mediaFileExtensions[".flac"], "audio/flac")
    }

    /// Verifies TaskbarProgressState values.
    func test_windowsPlatform_taskbarState() {
        XCTAssertEqual(WindowsPlatform.TaskbarProgressState.noProgress.rawValue, 0)
        XCTAssertEqual(WindowsPlatform.TaskbarProgressState.normal.rawValue, 2)
        XCTAssertEqual(WindowsPlatform.TaskbarProgressState.error.rawValue, 4)
    }

    // =========================================================================
    // MARK: - Phase 11: Linux Platform
    // =========================================================================

    /// Verifies LinuxDistro properties.
    func test_linuxDistro_properties() {
        XCTAssertEqual(LinuxDistro.ubuntu.displayName, "Ubuntu")
        XCTAssertEqual(LinuxDistro.ubuntu.packageManager, "apt")
        XCTAssertEqual(LinuxDistro.fedora.packageManager, "dnf")
        XCTAssertEqual(LinuxDistro.arch.packageManager, "pacman")
    }

    /// Verifies FFmpeg package names per distro.
    func test_linuxDistro_ffmpegPackage() {
        XCTAssertEqual(LinuxDistro.ubuntu.ffmpegPackageName, "ffmpeg")
        XCTAssertTrue(LinuxDistro.fedora.ffmpegPackageName.contains("ffmpeg"))
    }

    /// Verifies install commands.
    func test_linuxDistro_installCommand() {
        XCTAssertTrue(LinuxDistro.ubuntu.ffmpegInstallCommand.contains("apt"))
        XCTAssertTrue(LinuxDistro.fedora.ffmpegInstallCommand.contains("dnf"))
        XCTAssertTrue(LinuxDistro.arch.ffmpegInstallCommand.contains("pacman"))
    }

    /// Verifies LinuxDesktopEnvironment detection.
    func test_linuxDesktopEnvironment_detect() {
        let de = LinuxDesktopEnvironment.detect()
        // On macOS/non-Linux, this should return headless or unknown
        XCTAssertNotNil(de)
    }

    /// Verifies LinuxPackageFormat properties.
    func test_linuxPackageFormat_properties() {
        XCTAssertTrue(LinuxPackageFormat.flatpak.isSandboxed)
        XCTAssertTrue(LinuxPackageFormat.snap.isSandboxed)
        XCTAssertFalse(LinuxPackageFormat.deb.isSandboxed)
        XCTAssertFalse(LinuxPackageFormat.rpm.isSandboxed)
        XCTAssertFalse(LinuxPackageFormat.appImage.isSandboxed)
    }

    /// Verifies recommended package format per distro.
    func test_linuxPackageFormat_recommended() {
        XCTAssertEqual(LinuxPackageFormat.recommended(for: .ubuntu), .deb)
        XCTAssertEqual(LinuxPackageFormat.recommended(for: .debian), .deb)
        XCTAssertEqual(LinuxPackageFormat.recommended(for: .fedora), .rpm)
        XCTAssertEqual(LinuxPackageFormat.recommended(for: .unknown), .appImage)
    }

    /// Verifies VAAPI encode arguments.
    func test_linuxPlatform_vaapiEncodeArguments() {
        let args = LinuxPlatform.buildVAAPIEncodeArguments(
            codec: "h264_vaapi",
            devicePath: "/dev/dri/renderD128",
            quality: 20
        )
        XCTAssertTrue(args.contains("-vaapi_device"))
        XCTAssertTrue(args.contains("/dev/dri/renderD128"))
        XCTAssertTrue(args.contains("h264_vaapi"))
        XCTAssertTrue(args.contains(where: { $0.contains("hwupload") }))
        XCTAssertTrue(args.contains("20"))
    }

    /// Verifies VAAPI decode arguments.
    func test_linuxPlatform_vaapiDecodeArguments() {
        let args = LinuxPlatform.buildVAAPIDecodeArguments()
        XCTAssertTrue(args.contains("vaapi"))
        XCTAssertTrue(args.contains("/dev/dri/renderD128"))
    }

    /// Verifies V4L2 encode arguments for Raspberry Pi.
    func test_linuxPlatform_v4l2EncodeArguments() {
        let args = LinuxPlatform.buildV4L2EncodeArguments(
            codec: "h264_v4l2m2m",
            bitrate: 3000
        )
        XCTAssertTrue(args.contains("h264_v4l2m2m"))
        XCTAssertTrue(args.contains("3000k"))
    }

    /// Verifies Raspberry Pi memory-conscious settings.
    func test_linuxPlatform_rpiEncodingArgs() {
        let lowRam = LinuxPlatform.buildRPiEncodingArgs(availableRAM_MB: 1024)
        XCTAssertTrue(lowRam.contains("2")) // 2 threads
        XCTAssertTrue(lowRam.contains("-rc-lookahead"))

        let highRam = LinuxPlatform.buildRPiEncodingArgs(availableRAM_MB: 8192)
        XCTAssertTrue(highRam.contains("4")) // 4 threads
    }

    /// Verifies vainfo arguments.
    func test_linuxPlatform_vainfoArguments() {
        let args = LinuxPlatform.buildVainfoArguments(devicePath: "/dev/dri/renderD128")
        XCTAssertTrue(args.contains("--display"))
        XCTAssertTrue(args.contains("drm"))
    }

    /// Verifies desktop entry generation.
    func test_linuxPlatform_desktopEntry() {
        let entry = LinuxPlatform.generateDesktopEntry(
            execPath: "/usr/bin/meedya-convert",
            iconPath: "/usr/share/icons/meedyaconverter.png"
        )
        XCTAssertTrue(entry.contains("[Desktop Entry]"))
        XCTAssertTrue(entry.contains("MeedyaConverter"))
        XCTAssertTrue(entry.contains("AudioVideo"))
        XCTAssertTrue(entry.contains("/usr/bin/meedya-convert"))
    }

    /// Verifies udev rules generation.
    func test_linuxPlatform_udevRules() {
        let rules = LinuxPlatform.generateOpticalDiscUdevRules()
        XCTAssertTrue(rules.contains("SUBSYSTEM"))
        XCTAssertTrue(rules.contains("cdrom"))
        XCTAssertTrue(rules.contains("sr[0-9]*"))
    }

    /// Verifies udevadm arguments.
    func test_linuxPlatform_udevadmArguments() {
        let args = LinuxPlatform.buildUdevadmInfoArguments(devicePath: "/dev/sr0")
        XCTAssertTrue(args.contains("info"))
        XCTAssertTrue(args.contains { $0.contains("/dev/sr0") })
    }

    /// Verifies Flatpak permissions.
    func test_linuxPlatform_flatpakPermissions() {
        XCTAssertFalse(LinuxPlatform.flatpakPermissions.isEmpty)
        XCTAssertTrue(LinuxPlatform.flatpakPermissions.contains("--filesystem=home"))
        XCTAssertTrue(LinuxPlatform.flatpakPermissions.contains("--device=all"))
    }

    /// Verifies Snap plugs.
    func test_linuxPlatform_snapPlugs() {
        XCTAssertFalse(LinuxPlatform.snapPlugs.isEmpty)
        XCTAssertTrue(LinuxPlatform.snapPlugs.contains("home"))
        XCTAssertTrue(LinuxPlatform.snapPlugs.contains("removable-media"))
    }

    /// Verifies AppRun script generation.
    func test_linuxPlatform_appRunScript() {
        let script = LinuxPlatform.generateAppRunScript()
        XCTAssertTrue(script.contains("#!/bin/bash"))
        XCTAssertTrue(script.contains("meedya-convert"))
        XCTAssertTrue(script.contains("LD_LIBRARY_PATH"))
    }

    /// Verifies build dependencies lists.
    func test_linuxPlatform_buildDependencies() {
        XCTAssertFalse(LinuxPlatform.debianBuildDependencies.isEmpty)
        XCTAssertTrue(LinuxPlatform.debianBuildDependencies.contains("ffmpeg"))
        XCTAssertTrue(LinuxPlatform.debianBuildDependencies.contains("libgtk-4-dev"))

        XCTAssertFalse(LinuxPlatform.fedoraBuildDependencies.isEmpty)
        XCTAssertTrue(LinuxPlatform.fedoraBuildDependencies.contains("gtk4-devel"))
    }

    /// Verifies VAAPI device paths are defined.
    func test_linuxPlatform_devicePaths() {
        XCTAssertFalse(LinuxPlatform.vaapiDevicePaths.isEmpty)
        XCTAssertTrue(LinuxPlatform.vaapiDevicePaths.contains("/dev/dri/renderD128"))

        XCTAssertFalse(LinuxPlatform.v4l2DevicePaths.isEmpty)
        XCTAssertFalse(LinuxPlatform.opticalDriveDevices.isEmpty)
        XCTAssertTrue(LinuxPlatform.opticalDriveDevices.contains("/dev/sr0"))
    }

    /// Verifies WindowsInstallConfig defaults.
    func test_windowsInstallConfig_defaults() {
        let config = WindowsInstallConfig()
        XCTAssertEqual(config.appName, "MeedyaConverter")
        XCTAssertTrue(config.startMenuShortcut)
        XCTAssertTrue(config.fileAssociations)
        XCTAssertEqual(config.installerType, .msix)
    }

}
