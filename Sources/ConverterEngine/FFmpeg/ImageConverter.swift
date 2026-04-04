// ============================================================================
// MeedyaConverter — ImageConverter
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// MARK: - ImageFormat

/// Supported image formats for conversion.
public enum ImageFormat: String, Codable, Sendable, CaseIterable {
    case jpeg = "jpeg"
    case png = "png"
    case tiff = "tiff"
    case webp = "webp"
    case avif = "avif"
    case heif = "heif"
    case bmp = "bmp"
    case gif = "gif"
    case tga = "tga"
    case exr = "exr"
    case ppm = "ppm"
    case jpegXL = "jxl"

    /// File extension for this format.
    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .webp: return "webp"
        case .avif: return "avif"
        case .heif: return "heif"
        case .bmp: return "bmp"
        case .gif: return "gif"
        case .tga: return "tga"
        case .exr: return "exr"
        case .ppm: return "ppm"
        case .jpegXL: return "jxl"
        }
    }

    /// Display name.
    public var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .heif: return "HEIF/HEIC"
        case .bmp: return "BMP"
        case .gif: return "GIF"
        case .tga: return "TGA"
        case .exr: return "OpenEXR"
        case .ppm: return "PPM"
        case .jpegXL: return "JPEG XL"
        }
    }

    /// FFmpeg codec/encoder name for this format.
    public var ffmpegEncoder: String? {
        switch self {
        case .jpeg: return "mjpeg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .webp: return "libwebp"
        case .avif: return "libaom-av1"
        case .heif: return nil // Requires external tool
        case .bmp: return "bmp"
        case .gif: return "gif"
        case .tga: return "targa"
        case .exr: return "exr"
        case .ppm: return "ppm"
        case .jpegXL: return "libjxl"
        }
    }

    /// Whether this format supports lossless compression.
    public var supportsLossless: Bool {
        switch self {
        case .png, .tiff, .webp, .avif, .heif, .bmp, .tga, .exr, .ppm, .jpegXL:
            return true
        case .jpeg, .gif:
            return false
        }
    }

    /// Whether this format supports transparency (alpha channel).
    public var supportsAlpha: Bool {
        switch self {
        case .png, .webp, .avif, .heif, .tiff, .tga, .exr, .gif, .jpegXL:
            return true
        case .jpeg, .bmp, .ppm:
            return false
        }
    }

    /// Whether this format supports HDR (high dynamic range).
    public var supportsHDR: Bool {
        switch self {
        case .avif, .heif, .exr, .jpegXL, .tiff:
            return true
        default:
            return false
        }
    }

    /// Whether this format supports animation/multi-frame.
    public var supportsAnimation: Bool {
        switch self {
        case .gif, .webp, .avif, .jpegXL, .png: // APNG
            return true
        default:
            return false
        }
    }

    /// Detect format from file extension.
    public static func from(extension ext: String) -> ImageFormat? {
        let lower = ext.lowercased()
        switch lower {
        case "jpg", "jpeg": return .jpeg
        case "png", "apng": return .png
        case "tif", "tiff": return .tiff
        case "webp": return .webp
        case "avif": return .avif
        case "heif", "heic": return .heif
        case "bmp": return .bmp
        case "gif": return .gif
        case "tga": return .tga
        case "exr": return .exr
        case "ppm", "pgm", "pbm": return .ppm
        case "jxl": return .jpegXL
        default: return nil
        }
    }
}

// MARK: - ImageQuality

/// Quality settings for lossy image compression.
public struct ImageQuality: Codable, Sendable {
    /// Quality level (1–100). Higher = better quality, larger file.
    public var quality: Int

    /// Compression effort/speed (0–10). Higher = slower but smaller.
    public var effort: Int

    /// Whether to use lossless compression (if supported by format).
    public var lossless: Bool

    public init(quality: Int = 85, effort: Int = 6, lossless: Bool = false) {
        self.quality = max(1, min(100, quality))
        self.effort = max(0, min(10, effort))
        self.lossless = lossless
    }

    /// Preset quality levels.
    public static let low = ImageQuality(quality: 50, effort: 4)
    public static let medium = ImageQuality(quality: 75, effort: 6)
    public static let high = ImageQuality(quality: 90, effort: 7)
    public static let maximum = ImageQuality(quality: 100, effort: 9)
    public static let losslessPreset = ImageQuality(quality: 100, effort: 9, lossless: true)
}

// MARK: - ImageResizeMode

/// How to resize an image when dimensions change.
public enum ImageResizeMode: String, Codable, Sendable {
    /// Scale to exact dimensions (may distort).
    case exact = "exact"

    /// Scale to fit within dimensions (preserves aspect ratio, no crop).
    case fit = "fit"

    /// Scale to fill dimensions (preserves aspect ratio, may crop).
    case fill = "fill"

    /// Only downscale (never enlarge).
    case downscaleOnly = "downscale"
}

// MARK: - ImageConvertConfig

/// Configuration for an image conversion operation.
public struct ImageConvertConfig: Codable, Sendable {
    /// Output format.
    public var outputFormat: ImageFormat

    /// Quality settings.
    public var quality: ImageQuality

    /// Target width (nil = keep original).
    public var width: Int?

    /// Target height (nil = keep original).
    public var height: Int?

    /// Resize mode.
    public var resizeMode: ImageResizeMode

    /// Whether to strip EXIF/metadata from output.
    public var stripMetadata: Bool

    /// Whether to auto-rotate based on EXIF orientation.
    public var autoRotate: Bool

    /// Color profile conversion (e.g., "sRGB", "AdobeRGB", "DCI-P3").
    public var colorProfile: String?

    public init(
        outputFormat: ImageFormat = .jpeg,
        quality: ImageQuality = ImageQuality(),
        width: Int? = nil,
        height: Int? = nil,
        resizeMode: ImageResizeMode = .fit,
        stripMetadata: Bool = false,
        autoRotate: Bool = true,
        colorProfile: String? = nil
    ) {
        self.outputFormat = outputFormat
        self.quality = quality
        self.width = width
        self.height = height
        self.resizeMode = resizeMode
        self.stripMetadata = stripMetadata
        self.autoRotate = autoRotate
        self.colorProfile = colorProfile
    }
}

// MARK: - ImageConverter

/// Builds FFmpeg arguments for image format conversion, resizing, and
/// quality optimization.
///
/// Supports 12 image formats with lossy/lossless compression, resize
/// modes, metadata stripping, and HDR support.
///
/// Phase 17
public struct ImageConverter: Sendable {

    /// Build FFmpeg arguments for image conversion.
    ///
    /// - Parameters:
    ///   - inputPath: Source image path.
    ///   - outputPath: Output image path.
    ///   - config: Conversion configuration.
    /// - Returns: FFmpeg argument array.
    public static func buildConvertArguments(
        inputPath: String,
        outputPath: String,
        config: ImageConvertConfig
    ) -> [String] {
        var args: [String] = []

        args += ["-i", inputPath]

        // Build filter chain
        var filters: [String] = []

        // Auto-rotate from EXIF
        if config.autoRotate {
            // FFmpeg auto-rotates by default; explicitly disable if not wanted
        }

        // Resize
        if let w = config.width, let h = config.height {
            switch config.resizeMode {
            case .exact:
                filters.append("scale=\(w):\(h)")
            case .fit:
                filters.append("scale=\(w):\(h):force_original_aspect_ratio=decrease")
            case .fill:
                filters.append("scale=\(w):\(h):force_original_aspect_ratio=increase,crop=\(w):\(h)")
            case .downscaleOnly:
                filters.append("scale='min(\(w),iw)':'min(\(h),ih)':force_original_aspect_ratio=decrease")
            }
        } else if let w = config.width {
            filters.append("scale=\(w):-1")
        } else if let h = config.height {
            filters.append("scale=-1:\(h)")
        }

        if !filters.isEmpty {
            args += ["-vf", filters.joined(separator: ",")]
        }

        // Codec and quality
        if let encoder = config.outputFormat.ffmpegEncoder {
            args += ["-c:v", encoder]
        }

        // Format-specific quality settings
        args += buildQualityArguments(format: config.outputFormat, quality: config.quality)

        // Metadata
        if config.stripMetadata {
            args += ["-map_metadata", "-1"]
        }

        // Single frame output
        args += ["-frames:v", "1"]
        args += ["-update", "1"]

        args += ["-y", outputPath]

        return args
    }

    /// Build FFmpeg arguments for batch image conversion.
    ///
    /// - Parameters:
    ///   - inputPattern: Input glob pattern (e.g., "/tmp/images/*.jpg").
    ///   - outputDir: Output directory.
    ///   - config: Conversion configuration.
    /// - Returns: (arguments, outputPattern) for batch processing.
    public static func buildBatchArguments(
        outputDir: String,
        config: ImageConvertConfig
    ) -> [String] {
        // For batch, the caller should iterate files and call buildConvertArguments
        // This method provides the common arguments template
        var args: [String] = []

        if let encoder = config.outputFormat.ffmpegEncoder {
            args += ["-c:v", encoder]
        }

        args += buildQualityArguments(format: config.outputFormat, quality: config.quality)

        if config.stripMetadata {
            args += ["-map_metadata", "-1"]
        }

        return args
    }

    /// Build a video thumbnail extraction filter.
    ///
    /// Extracts a single frame from a video at a given timestamp.
    ///
    /// - Parameters:
    ///   - inputPath: Video file path.
    ///   - outputPath: Output image path.
    ///   - timestamp: Time offset in seconds.
    ///   - format: Output image format.
    ///   - width: Optional resize width.
    ///   - height: Optional resize height.
    /// - Returns: FFmpeg argument array.
    public static func buildThumbnailArguments(
        inputPath: String,
        outputPath: String,
        timestamp: TimeInterval = 0,
        format: ImageFormat = .jpeg,
        width: Int? = nil,
        height: Int? = nil
    ) -> [String] {
        var args: [String] = []

        args += ["-ss", String(format: "%.2f", timestamp)]
        args += ["-i", inputPath]

        var filters: [String] = []
        if let w = width, let h = height {
            filters.append("scale=\(w):\(h):force_original_aspect_ratio=decrease")
        } else if let w = width {
            filters.append("scale=\(w):-1")
        }

        if !filters.isEmpty {
            args += ["-vf", filters.joined(separator: ",")]
        }

        args += ["-frames:v", "1"]

        if let encoder = format.ffmpegEncoder {
            args += ["-c:v", encoder]
        }

        if format == .jpeg {
            args += ["-q:v", "2"] // High quality JPEG
        }

        args += ["-y", outputPath]

        return args
    }

    /// Check if a file extension is a supported image format.
    public static func isImageFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension
        return ImageFormat.from(extension: ext) != nil
    }

    /// Recommend the best output format based on requirements.
    ///
    /// - Parameters:
    ///   - needsAlpha: Whether transparency is needed.
    ///   - needsHDR: Whether HDR is needed.
    ///   - needsAnimation: Whether animation is needed.
    ///   - preferSmallSize: Whether file size is a priority.
    /// - Returns: The recommended format.
    public static func recommendFormat(
        needsAlpha: Bool = false,
        needsHDR: Bool = false,
        needsAnimation: Bool = false,
        preferSmallSize: Bool = false
    ) -> ImageFormat {
        if needsHDR && needsAlpha {
            return .avif
        }
        if needsHDR {
            return .avif
        }
        if needsAnimation {
            return preferSmallSize ? .webp : .gif
        }
        if needsAlpha {
            return preferSmallSize ? .webp : .png
        }
        if preferSmallSize {
            return .webp
        }
        return .jpeg
    }

    // MARK: - Private

    private static func buildQualityArguments(
        format: ImageFormat,
        quality: ImageQuality
    ) -> [String] {
        var args: [String] = []

        switch format {
        case .jpeg:
            // MJPEG quality: 2 (best) to 31 (worst)
            let q = 2 + (31 - 2) * (100 - quality.quality) / 100
            args += ["-q:v", "\(q)"]

        case .webp:
            if quality.lossless {
                args += ["-lossless", "1"]
            } else {
                args += ["-quality", "\(quality.quality)"]
            }
            args += ["-compression_level", "\(quality.effort)"]

        case .avif:
            if quality.lossless {
                args += ["-crf", "0"]
            } else {
                // CRF for AVIF: 0 (lossless) to 63 (worst)
                let crf = Int(Double(63) * Double(100 - quality.quality) / 100.0)
                args += ["-crf", "\(crf)"]
            }
            args += ["-still-picture", "1"]

        case .png:
            // PNG compression level: 0 (none) to 9 (max)
            let level = quality.effort * 9 / 10
            args += ["-compression_level", "\(level)"]

        case .tiff:
            if quality.lossless {
                args += ["-compression_algo", "lzw"]
            }

        case .jpegXL:
            if quality.lossless {
                args += ["-distance", "0"]
            } else {
                // Distance: 0 (lossless) to 15 (worst)
                let dist = String(format: "%.1f", Double(15) * Double(100 - quality.quality) / 100.0)
                args += ["-distance", dist]
            }
            args += ["-effort", "\(quality.effort)"]

        default:
            break
        }

        return args
    }
}
