// ============================================================================
// MeedyaConverter — AutomatorIntegration (macOS Services Provider)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

// ---------------------------------------------------------------------------
// MARK: - File Overview
// ---------------------------------------------------------------------------
// Registers MeedyaConverter as a macOS Services provider so users can
// right-click media files in Finder and select "Encode with MeedyaConverter"
// from the Services submenu.
//
// This integration enables:
//   - Finder context menu encoding via the Services menu.
//   - Hazel rule integration (Hazel can invoke Services actions).
//   - Folder Action-style workflows without requiring a separate bundle.
//
// The service accepts file URLs from the pasteboard, passes them to the
// EncodeMediaActionHandler, and writes the output URLs back.
//
// To register the service, the app's Info.plist must include an NSServices
// entry (see comments in registerServices()). For SPM-based builds, this
// is configured in the Resources/Info.plist file.
//
// Phase 11 / Issue #357
// ---------------------------------------------------------------------------

import AppKit
import Foundation
import ConverterEngine

// MARK: - AutomatorIntegration

/// Registers and handles macOS Services menu integration for MeedyaConverter.
///
/// When registered, the app appears in the Finder's Services submenu for
/// supported file types (video, audio, image). Selecting the service sends
/// the selected file URLs to MeedyaConverter for encoding.
///
/// ### Registration
/// Call `AutomatorIntegration.registerServices()` during app launch to
/// register the service provider with NSApplication. The Info.plist must
/// also declare the service via the `NSServices` key.
///
/// ### Info.plist NSServices Entry
/// ```xml
/// <key>NSServices</key>
/// <array>
///     <dict>
///         <key>NSMessage</key>
///         <string>handleServiceRequest</string>
///         <key>NSMenuItem</key>
///         <dict>
///             <key>default</key>
///             <string>Encode with MeedyaConverter</string>
///         </dict>
///         <key>NSSendTypes</key>
///         <array>
///             <string>NSFilenamesPboardType</string>
///             <string>public.file-url</string>
///         </array>
///         <key>NSReturnTypes</key>
///         <array>
///             <string>NSFilenamesPboardType</string>
///         </array>
///     </dict>
/// </array>
/// ```
struct AutomatorIntegration {

    // MARK: - Service Registration

    /// Register MeedyaConverter as a macOS Services provider.
    ///
    /// This method:
    /// 1. Creates a `ServiceProvider` instance as the service handler.
    /// 2. Registers it with `NSApplication` via `registerServicesMenuSendTypes`.
    /// 3. Sets the provider on `NSApp` so macOS knows to route service
    ///    requests to this application.
    ///
    /// Must be called on the main thread during application launch (e.g. in
    /// the `@main` app struct's initialiser or `applicationDidFinishLaunching`).
    ///
    /// - Note: The actual service will not appear in Finder's Services menu
    ///   until the app has been launched at least once and macOS has indexed
    ///   the app's Info.plist NSServices declaration.
    @MainActor
    static func registerServices() {
        // Register the pasteboard types this app can receive via Services.
        // NSFilenamesPboardType is the legacy type for file paths.
        // public.file-url is the modern UTI-based type.
        NSApp.registerServicesMenuSendTypes(
            [.fileURL, .string],
            returnTypes: [.string]
        )

        // Create and register the service provider singleton.
        let provider = ServiceProvider.shared
        NSApp.servicesProvider = provider

        // Force macOS to re-read services (updates the Services menu).
        NSUpdateDynamicServices()
    }

    /// Handle a service request from the macOS Services menu.
    ///
    /// This is a convenience wrapper around `ServiceProvider.handleServiceRequest`.
    /// It extracts file URLs from the pasteboard, encodes them with the
    /// default profile, and writes the output paths back to the pasteboard.
    ///
    /// - Parameters:
    ///   - pasteboard: The pasteboard containing the input file URLs.
    ///   - userData: Optional user data string from the NSServices plist entry.
    ///     Can specify a profile name (e.g. "Web Standard").
    @MainActor
    static func handleServiceRequest(pasteboard: NSPasteboard, userData: String) {
        ServiceProvider.shared.handleServiceRequest(
            pasteboard,
            userData: userData,
            error: nil
        )
    }
}

// MARK: - ServiceProvider

/// The Objective-C compatible service provider that handles incoming
/// Services menu requests from macOS.
///
/// This class must be `NSObject` because `NSApplication.servicesProvider`
/// requires an Objective-C object with methods matching the `NSMessage`
/// selectors declared in the Info.plist NSServices entry.
@MainActor
final class ServiceProvider: NSObject {

    // MARK: - Properties

    /// Shared singleton instance registered as the services provider.
    static let shared = ServiceProvider()

    /// The action handler used to encode files received via Services.
    let actionHandler = EncodeMediaActionHandler()

    /// The default profile name used when no profile is specified
    /// in the service request's userData.
    var defaultProfileName: String = "Web Standard"

    // MARK: - Service Handler

    /// Handle a service request from the macOS Services menu.
    ///
    /// This method is called by macOS when the user selects
    /// "Encode with MeedyaConverter" from the Services submenu in Finder.
    ///
    /// - Parameters:
    ///   - pboard: The pasteboard containing the selected file URLs.
    ///   - userData: Optional string from the NSServices plist. If non-empty,
    ///     it is interpreted as the encoding profile name.
    ///   - error: An autoreleasing error pointer for reporting failures
    ///     back to the Services framework. Set to a user-readable message
    ///     if the operation fails.
    @objc func handleServiceRequest(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        // Determine which profile to use
        let profileName: String
        if let userData = userData, !userData.isEmpty {
            profileName = userData
        } else {
            profileName = defaultProfileName
        }

        // Extract file URLs from the pasteboard
        let fileURLs = extractFileURLs(from: pboard)
        guard !fileURLs.isEmpty else {
            error?.pointee = "No supported files were found in the selection." as NSString
            return
        }

        // Run the encoding asynchronously
        Task { @MainActor in
            do {
                let outputURLs = try await actionHandler.handle(
                    input: fileURLs,
                    profileName: profileName
                )

                // Write output URLs back to the pasteboard so downstream
                // services or Automator actions can use them.
                if !outputURLs.isEmpty {
                    pboard.clearContents()
                    pboard.writeObjects(outputURLs.map(\.absoluteString) as [NSString])
                }
            } catch {
                // Log the error — we can't set the error pointer asynchronously,
                // but the user will see the result (or lack thereof) in Finder.
                NSLog(
                    "MeedyaConverter Services error: %@",
                    error.localizedDescription
                )
            }
        }
    }

    // MARK: - Pasteboard Extraction

    /// Extract file URLs from an NSPasteboard.
    ///
    /// Handles both modern `public.file-url` types and legacy
    /// `NSFilenamesPboardType` strings.
    ///
    /// - Parameter pasteboard: The pasteboard to read from.
    /// - Returns: An array of file URLs found on the pasteboard.
    private func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        // Try modern file URL reading first
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }

        // Fall back to legacy filename strings
        if let filenames = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            return filenames.map { URL(fileURLWithPath: $0) }
        }

        return []
    }
}
