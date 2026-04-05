// ============================================================================
// MeedyaConverter — ThemeSettingsView (Issue #336)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI

// MARK: - ThemeSettingsView

/// Settings view for customising the application's colour theme.
///
/// Provides a colour picker for the accent colour, a grid of preset
/// themes, an optional sidebar tint picker, a live preview swatch,
/// and a reset-to-default button.
///
/// Phase 15 — Color Theme Customization (Issue #336)
struct ThemeSettingsView: View {

    // MARK: - Environment

    /// The shared theme manager that holds and persists theme state.
    @State private var themeManager = ThemeManager()

    // MARK: - State

    /// Tracks the accent colour in the colour picker independently
    /// so that the picker updates smoothly without lag.
    @State private var pickerAccent: Color = .accentColor

    /// Whether the sidebar tint option is enabled.
    @State private var sidebarTintEnabled = false

    /// The sidebar tint colour picker value.
    @State private var pickerSidebarTint: Color = .blue

    // MARK: - Body

    var body: some View {
        Form {
            // MARK: Accent Colour
            Section("Accent Colour") {
                ColorPicker(
                    "Accent Colour",
                    selection: $pickerAccent,
                    supportsOpacity: false
                )
                .accessibilityLabel("Accent colour picker")
                .onChange(of: pickerAccent) { _, newValue in
                    themeManager.accentColor = newValue
                }
            }

            // MARK: Sidebar Tint
            Section("Sidebar Tint") {
                Toggle("Enable sidebar tint", isOn: $sidebarTintEnabled)
                    .accessibilityLabel("Toggle sidebar tint")
                    .onChange(of: sidebarTintEnabled) { _, enabled in
                        themeManager.sidebarTint = enabled ? pickerSidebarTint : nil
                    }

                if sidebarTintEnabled {
                    ColorPicker(
                        "Sidebar Tint",
                        selection: $pickerSidebarTint,
                        supportsOpacity: false
                    )
                    .accessibilityLabel("Sidebar tint colour picker")
                    .onChange(of: pickerSidebarTint) { _, newValue in
                        themeManager.sidebarTint = newValue
                    }
                }
            }

            // MARK: Preset Themes
            Section("Preset Themes") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100))],
                    spacing: 12
                ) {
                    ForEach(ThemeManager.presetThemes) { theme in
                        presetCard(theme)
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: Preview
            Section("Preview") {
                HStack(spacing: 16) {
                    // Accent colour swatch
                    VStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(themeManager.accentColor)
                            .frame(width: 60, height: 40)
                        Text("Accent")
                            .font(.caption)
                    }

                    // Sidebar tint swatch
                    VStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(themeManager.sidebarTint ?? Color.gray.opacity(0.3))
                            .frame(width: 60, height: 40)
                        Text("Sidebar")
                            .font(.caption)
                    }

                    // Sample button preview
                    VStack {
                        Button("Sample") {}
                            .tint(themeManager.accentColor)
                            .buttonStyle(.borderedProminent)
                        Text("Button")
                            .font(.caption)
                    }

                    Spacer()

                    if let theme = themeManager.customTheme {
                        Text("Theme: \(theme.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: Reset
            Section {
                Button("Reset to System Default") {
                    themeManager.resetToDefault()
                    pickerAccent = .accentColor
                    sidebarTintEnabled = false
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            pickerAccent = themeManager.accentColor
            if let tint = themeManager.sidebarTint {
                sidebarTintEnabled = true
                pickerSidebarTint = tint
            }
        }
    }

    // MARK: - Preset Card

    /// A visual card representing a preset theme in the grid.
    ///
    /// Displays the theme's accent colour as a filled circle with the
    /// theme name below. Tapping applies the theme.
    ///
    /// - Parameter theme: The preset theme to display.
    /// - Returns: A view for the preset card.
    private func presetCard(_ theme: CustomTheme) -> some View {
        Button {
            themeManager.apply(theme: theme)
            pickerAccent = themeManager.accentColor
            if let tint = themeManager.sidebarTint {
                sidebarTintEnabled = true
                pickerSidebarTint = tint
            } else {
                sidebarTintEnabled = false
            }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: theme.accentHex))
                    .frame(width: 36, height: 36)
                    .overlay {
                        if themeManager.customTheme?.id == theme.id {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }

                Text(theme.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(themeManager.customTheme?.id == theme.id
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply \(theme.name) theme")
    }
}
