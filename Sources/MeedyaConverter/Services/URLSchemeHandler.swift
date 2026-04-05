// ============================================================================
// MeedyaConverter — URLSchemeHandler (Issue #356)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================

import SwiftUI
import ConverterEngine

// ---------------------------------------------------------------------------
// MARK: - URLSchemeAction
// ---------------------------------------------------------------------------
/// Actions that can be triggered via the `meedyaconverter://` URL scheme.
///
/// Each case maps to a URL host component:
/// - `meedyaconverter://encode?file=...&profile=...`
/// - `meedyaconverter://probe?file=...`
/// - `meedyaconverter://open?view=queue`
///
/// Phase 16 — URL Scheme Handler (Issue #356)
enum URLSchemeAction: Sendable {

    /// Start an encoding job for the specified file with an optional profile.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the source media file.
    ///   - profile: Optional encoding profile name to apply.
    case encode(filePath: String, profile: String?)

    /// Probe a media file and display its stream information.
    ///
    /// - Parameter filePath: Absolute path to the media file to probe.
    case probe(filePath: String)

    /// Navigate to a specific view within the application.
    ///
    /// - Parameter viewName: The view identifier (e.g., "queue", "settings",
    ///   "dashboard").
    case open(viewName: String)
}

// ---------------------------------------------------------------------------
// MARK: - URLSchemeError
// ---------------------------------------------------------------------------
/// Errors encountered while parsing or handling URL scheme requests.
///
/// Phase 16 — URL Scheme Handler (Issue #356)
enum URLSchemeError: LocalizedError, Sendable {

    /// The URL scheme is not `meedyaconverter`.
    case unsupportedScheme(String)

    /// The URL host (action) is not recognised.
    case unknownAction(String)

    /// A required query parameter is missing.
    case missingParameter(String)

    /// The specified file path does not exist on disk.
    case fileNotFound(String)

    /// Human-readable description of the error.
    var errorDescription: String? {
        switch self {
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme). Expected 'meedyaconverter'."
        case .unknownAction(let action):
            return "Unknown URL action: \(action). Supported actions: encode, probe, open."
        case .missingParameter(let param):
            return "Missing required URL parameter: '\(param)'."
        case .fileNotFound(let path):
            return "File not found: \(path)."
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - URLSchemeHandler
// ---------------------------------------------------------------------------
/// Handles `meedyaconverter://` URLs to allow external automation and
/// inter-app communication.
///
/// Registered URL schemes:
/// - `meedyaconverter://encode?file=/path/to/video.mov&profile=Web%20Standard`
/// - `meedyaconverter://probe?file=/path/to/video.mov`
/// - `meedyaconverter://open?view=queue`
///
/// The handler parses incoming URLs, validates parameters, and routes
/// actions to the appropriate `AppViewModel` methods. Invalid or
/// malformed URLs produce descriptive errors.
///
/// Usage from the SwiftUI `App` struct:
/// ```swift
/// .onOpenURL { url in
///     urlSchemeHandler.handleURL(url)
/// }
/// ```
///
/// Phase 16 — URL Scheme Handler (Issue #356)
@MainActor
final class URLSchemeHandler {

    // MARK: - Constants

    /// The registered URL scheme for MeedyaConverter.
    static let scheme = "meedyaconverter"

    // MARK: - Properties

    /// The most recent error encountered during URL handling.
    ///
    /// Views can observe this to display error alerts when a URL
    /// scheme request fails.
    var lastError: URLSchemeError?

    /// The most recently parsed action, for debugging/logging purposes.
    var lastAction: URLSchemeAction?

    // MARK: - URL Handling

    /// Parses and handles an incoming URL.
    ///
    /// Validates the scheme, extracts the action from the host component,
    /// and routes to the appropriate handler method. Returns `true` if the
    /// URL was successfully handled, `false` otherwise.
    ///
    /// - Parameter url: The incoming URL to process.
    /// - Returns: `true` if the URL was successfully processed.
    @discardableResult
    func handleURL(_ url: URL) -> Bool {
        lastError = nil

        // Validate the URL scheme.
        guard let scheme = url.scheme?.lowercased(),
              scheme == Self.scheme else {
            lastError = .unsupportedScheme(url.scheme ?? "nil")
            return false
        }

        // Extract the action from the host component.
        guard let action = url.host?.lowercased() else {
            lastError = .unknownAction("nil")
            return false
        }

        // Parse query parameters into a dictionary.
        let params = parseQueryParameters(from: url)

        // Route to the appropriate action handler.
        do {
            let parsedAction = try parseAction(action, params: params)
            lastAction = parsedAction
            routeAction(parsedAction)
            return true
        } catch let error as URLSchemeError {
            lastError = error
            return false
        } catch {
            lastError = .unknownAction(action)
            return false
        }
    }

    // MARK: - Parsing

    /// Parses the URL action and query parameters into a `URLSchemeAction`.
    ///
    /// - Parameters:
    ///   - action: The host component of the URL (e.g., "encode").
    ///   - params: Dictionary of query parameter key-value pairs.
    /// - Returns: A typed `URLSchemeAction`.
    /// - Throws: `URLSchemeError` if the action is unknown or required
    ///   parameters are missing.
    private func parseAction(
        _ action: String,
        params: [String: String]
    ) throws -> URLSchemeAction {
        switch action {
        case "encode":
            guard let filePath = params["file"] else {
                throw URLSchemeError.missingParameter("file")
            }
            guard FileManager.default.fileExists(atPath: filePath) else {
                throw URLSchemeError.fileNotFound(filePath)
            }
            return .encode(filePath: filePath, profile: params["profile"])

        case "probe":
            guard let filePath = params["file"] else {
                throw URLSchemeError.missingParameter("file")
            }
            guard FileManager.default.fileExists(atPath: filePath) else {
                throw URLSchemeError.fileNotFound(filePath)
            }
            return .probe(filePath: filePath)

        case "open":
            guard let viewName = params["view"] else {
                throw URLSchemeError.missingParameter("view")
            }
            return .open(viewName: viewName)

        default:
            throw URLSchemeError.unknownAction(action)
        }
    }

    /// Extracts query parameters from a URL into a dictionary.
    ///
    /// Handles percent-encoded values and duplicate keys (last value wins).
    ///
    /// - Parameter url: The URL to extract parameters from.
    /// - Returns: A dictionary mapping parameter names to their values.
    private func parseQueryParameters(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }
        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }
        return params
    }

    // MARK: - Routing

    /// Routes a parsed action to the appropriate application behaviour.
    ///
    /// In the current implementation, this method logs the action. When
    /// integrated with `AppViewModel`, it will call the corresponding
    /// methods to trigger encoding, probing, or navigation.
    ///
    /// - Parameter action: The parsed URL scheme action to execute.
    private func routeAction(_ action: URLSchemeAction) {
        switch action {
        case .encode(let filePath, let profile):
            // Integration point: trigger encoding via AppViewModel.
            // viewModel.importFile(at: URL(fileURLWithPath: filePath))
            // if let profile = profile {
            //     viewModel.selectProfile(named: profile)
            // }
            // viewModel.startEncoding()
            _ = (filePath, profile)

        case .probe(let filePath):
            // Integration point: trigger media probing via AppViewModel.
            // viewModel.importFile(at: URL(fileURLWithPath: filePath))
            // viewModel.selectedNavItem = .source
            _ = filePath

        case .open(let viewName):
            // Integration point: navigate to the requested view.
            // viewModel.selectedNavItem = NavigationItem(rawValue: viewName)
            _ = viewName
        }
    }
}
