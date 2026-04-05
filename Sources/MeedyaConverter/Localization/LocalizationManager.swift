// ============================================================================
// MeedyaConverter — LocalizationManager (Issue #303)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import Foundation

// ---------------------------------------------------------------------------
// MARK: - LocalizationManager
// ---------------------------------------------------------------------------
/// Manages in-app language selection and provides localised string access.
///
/// Serves as the central hub for MeedyaConverter's internationalisation
/// (i18n) infrastructure. Tracks the user's preferred language, maintains
/// the list of supported locales, and provides helper methods for
/// resolving localised strings at runtime.
///
/// ## Architecture
///
/// Full localisation in a shipping app uses Xcode's String Catalog
/// (`.xcstrings`) system, which maps `LocalizedStringKey` values to
/// translated strings per locale. This manager provides the programmatic
/// layer for:
/// - Switching the active language at runtime (without restarting)
/// - Persisting the user's language preference in `UserDefaults`
/// - Resolving strings from the app's `.lproj` bundles
///
/// ## Supported Languages
///
/// | Code     | Language              |
/// |----------|-----------------------|
/// | en       | English               |
/// | es       | Spanish               |
/// | fr       | French                |
/// | de       | German                |
/// | ja       | Japanese              |
/// | zh-Hans  | Chinese (Simplified)  |
///
/// Phase 9 — Localization / i18n Support (Issue #303)
@MainActor
@Observable
final class LocalizationManager {

    // MARK: - Singleton

    /// Shared instance for app-wide locale management.
    static let shared = LocalizationManager()

    // MARK: - Properties

    /// The currently active locale, reflecting the user's language choice.
    ///
    /// Changing this value triggers SwiftUI views to re-render with the
    /// new locale's strings (when using `LocalizedStringKey`).
    var currentLocale: Locale

    /// The list of language codes this app supports.
    ///
    /// Each code corresponds to an `.lproj` directory containing a
    /// `Localizable.strings` file with translated key-value pairs.
    var supportedLanguages: [String] = [
        "en",
        "es",
        "fr",
        "de",
        "ja",
        "zh-Hans",
    ]

    // MARK: - Private

    /// UserDefaults key for persisting the selected language.
    private static let languageKey = "com.mwbm.meedyaconverter.selectedLanguage"

    // MARK: - Initialisation

    /// Creates the localization manager, restoring the previously selected
    /// language from UserDefaults if available.
    private init() {
        let saved = UserDefaults.standard.string(
            forKey: LocalizationManager.languageKey
        )
        if let saved {
            self.currentLocale = Locale(identifier: saved)
        } else {
            self.currentLocale = Locale.current
        }
    }

    // MARK: - Language Selection

    /// Sets the active language and persists the choice.
    ///
    /// If the provided code is not in `supportedLanguages`, the method
    /// falls back to English ("en").
    ///
    /// - Parameter code: ISO 639-1 language code (e.g., "en", "ja", "zh-Hans").
    func setLanguage(_ code: String) {
        let effectiveCode = supportedLanguages.contains(code) ? code : "en"
        currentLocale = Locale(identifier: effectiveCode)
        UserDefaults.standard.set(effectiveCode, forKey: LocalizationManager.languageKey)
    }

    // MARK: - String Resolution

    /// Returns the localised string for the given key using the current locale.
    ///
    /// Looks up the key in the `Localizable.strings` file corresponding
    /// to the active locale. If no translation is found, the key itself
    /// is returned as a fallback.
    ///
    /// - Parameter key: The localisation key defined in `Localizable.strings`.
    /// - Returns: The localised string, or the key if no translation exists.
    static func localizedString(_ key: String) -> String {
        // Attempt to find the .lproj bundle for the current locale
        let languageCode = LocalizationManager.shared.currentLocale.language.languageCode?.identifier ?? "en"

        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }

        // Fallback: use the main bundle's default localisation
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    // MARK: - Display Helpers

    /// Returns the display name for a language code in the language's own locale.
    ///
    /// For example, "ja" returns "?????????", "de" returns "Deutsch".
    ///
    /// - Parameter code: ISO 639-1 language code.
    /// - Returns: The localised language name, or the code if unavailable.
    func displayName(for code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code) ?? code
    }

    /// Returns the display name for a language code in the current UI locale.
    ///
    /// For example, in English, "ja" returns "Japanese".
    ///
    /// - Parameter code: ISO 639-1 language code.
    /// - Returns: The language name in the current locale.
    func localizedDisplayName(for code: String) -> String {
        currentLocale.localizedString(forLanguageCode: code) ?? code
    }

    /// The currently active language code (e.g., "en", "ja").
    var currentLanguageCode: String {
        currentLocale.language.languageCode?.identifier ?? "en"
    }

    /// Whether the current locale uses a right-to-left layout direction.
    var isRightToLeft: Bool {
        Locale.Language(identifier: currentLanguageCode).characterDirection == .rightToLeft
    }
}
