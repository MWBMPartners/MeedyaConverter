// ============================================================================
// MeedyaConverter — ThemeManager (Issue #336)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI

// MARK: - CustomTheme

/// A user-defined or preset colour theme for the application.
///
/// Themes store colours as hex strings for `Codable` serialisation.
/// The accent colour tints controls and selection highlights, while
/// the optional sidebar tint customises the sidebar background.
///
/// Phase 15 — Color Theme Customization (Issue #336)
public struct CustomTheme: Codable, Sendable, Identifiable, Hashable {

    /// Unique identifier for this theme.
    public let id: UUID

    /// The display name of the theme (e.g. "Ocean", "Sunset").
    public let name: String

    /// The accent colour as a hex string (e.g. "#0A84FF").
    public let accentHex: String

    /// An optional sidebar tint colour as a hex string.
    public let sidebarTintHex: String?

    /// Creates a new custom theme.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - name: The display name.
    ///   - accentHex: Accent colour hex string.
    ///   - sidebarTintHex: Optional sidebar tint hex string.
    public init(
        id: UUID = UUID(),
        name: String,
        accentHex: String,
        sidebarTintHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.sidebarTintHex = sidebarTintHex
    }
}

// MARK: - ThemeManager

/// Manages the application's colour theme, including accent colour,
/// sidebar tint, and preset themes.
///
/// Persists the selected accent colour and custom theme to
/// `UserDefaults` so the user's choice survives app restarts.
/// Provides five built-in preset themes and allows applying
/// or resetting themes at runtime.
///
/// Phase 15 — Color Theme Customization (Issue #336)
@MainActor @Observable
final class ThemeManager {

    // MARK: - Properties

    /// The current accent colour applied to tinted controls and selections.
    var accentColor: Color {
        didSet {
            UserDefaults.standard.set(accentColor.toHex(), forKey: "customAccentColor")
        }
    }

    /// An optional tint colour for the sidebar background.
    var sidebarTint: Color? {
        didSet {
            UserDefaults.standard.set(sidebarTint?.toHex(), forKey: "customSidebarTint")
        }
    }

    /// The currently applied custom theme, or `nil` for the system default.
    var customTheme: CustomTheme? {
        didSet {
            if let theme = customTheme,
               let data = try? JSONEncoder().encode(theme) {
                UserDefaults.standard.set(data, forKey: "customThemeData")
            } else {
                UserDefaults.standard.removeObject(forKey: "customThemeData")
            }
        }
    }

    // MARK: - Preset Themes

    /// Built-in preset themes available for quick selection.
    ///
    /// Each preset provides a curated accent colour and optional sidebar
    /// tint designed around a specific aesthetic.
    static let presetThemes: [CustomTheme] = [
        CustomTheme(
            name: "Ocean",
            accentHex: "#0A84FF",
            sidebarTintHex: "#0D2137"
        ),
        CustomTheme(
            name: "Sunset",
            accentHex: "#FF6B35",
            sidebarTintHex: "#3D1A00"
        ),
        CustomTheme(
            name: "Forest",
            accentHex: "#30D158",
            sidebarTintHex: "#0A2E14"
        ),
        CustomTheme(
            name: "Mono",
            accentHex: "#8E8E93",
            sidebarTintHex: nil
        ),
        CustomTheme(
            name: "Neon",
            accentHex: "#BF5AF2",
            sidebarTintHex: "#1A0A2E"
        ),
    ]

    // MARK: - Initialisation

    /// Creates the theme manager, restoring persisted preferences.
    init() {
        // Restore accent colour from UserDefaults
        if let hex = UserDefaults.standard.string(forKey: "customAccentColor") {
            self.accentColor = Color(hex: hex)
        } else {
            self.accentColor = .accentColor
        }

        // Restore sidebar tint
        if let hex = UserDefaults.standard.string(forKey: "customSidebarTint") {
            self.sidebarTint = Color(hex: hex)
        } else {
            self.sidebarTint = nil
        }

        // Restore custom theme
        if let data = UserDefaults.standard.data(forKey: "customThemeData"),
           let theme = try? JSONDecoder().decode(CustomTheme.self, from: data) {
            self.customTheme = theme
        } else {
            self.customTheme = nil
        }
    }

    // MARK: - Actions

    /// Applies a preset or custom theme, updating the accent colour
    /// and sidebar tint to match.
    ///
    /// - Parameter theme: The theme to apply.
    func apply(theme: CustomTheme) {
        customTheme = theme
        accentColor = Color(hex: theme.accentHex)
        sidebarTint = theme.sidebarTintHex.map { Color(hex: $0) }
    }

    /// Resets the theme to the system default, clearing all customisations.
    func resetToDefault() {
        customTheme = nil
        accentColor = .accentColor
        sidebarTint = nil
        UserDefaults.standard.removeObject(forKey: "customAccentColor")
        UserDefaults.standard.removeObject(forKey: "customSidebarTint")
        UserDefaults.standard.removeObject(forKey: "customThemeData")
    }
}

// MARK: - Color Hex Extensions

/// Extends `Color` with hex string conversion for persistence.
extension Color {

    /// Creates a `Color` from a hex string (e.g. "#FF5733" or "FF5733").
    ///
    /// Supports 6-character (RGB) and 8-character (ARGB) hex strings.
    /// Returns a fallback grey if the string cannot be parsed.
    ///
    /// - Parameter hex: The hex colour string.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r: Double
        let g: Double
        let b: Double
        let a: Double

        if cleaned.count == 8 {
            a = Double((rgb >> 24) & 0xFF) / 255.0
            r = Double((rgb >> 16) & 0xFF) / 255.0
            g = Double((rgb >> 8) & 0xFF) / 255.0
            b = Double(rgb & 0xFF) / 255.0
        } else {
            a = 1.0
            r = Double((rgb >> 16) & 0xFF) / 255.0
            g = Double((rgb >> 8) & 0xFF) / 255.0
            b = Double(rgb & 0xFF) / 255.0
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Converts this colour to a 6-character hex string with a `#` prefix.
    ///
    /// Falls back to `#808080` if the colour cannot be resolved.
    ///
    /// - Returns: A hex string representation (e.g. "#0A84FF").
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?
            .cgColor.components, components.count >= 3 else {
            return "#808080"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
