// ============================================================================
// MeedyaConverter — ScriptingCommands (Issue #302)
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// The `NSScriptCommand` subclasses the `.sdef` binds each verb to via its
// `<cocoa class="…"/>` elements. Each reads its parameters from the live Apple
// Event and forwards to `ScriptingBridge.shared` (whose engine/queue/profile
// store are wired in `AppViewModel.init`). This is the layer that was missing
// for #302: the `.sdef` and `ScriptingBridge` existed, but no command class
// connected an incoming Apple Event to the bridge, and the app was not marked
// scriptable (Info.plist `NSAppleScriptEnabled`/`OSAScriptingDefinition`).
//
// Apple-Event dispatch runs on the main thread (the NSApplication event loop),
// so `performDefaultImplementation()` — a nonisolated ObjC override — reaches
// the `@MainActor` bridge via `MainActor.assumeIsolated`, which is sound here
// precisely because OSA never dispatches these off the main thread.
//
// Argument lookup is deliberately defensive: `evaluatedArguments` may be keyed
// by a parameter's four-character `code` or by its `name` depending on the OSA
// path, so each argument is looked up under both. `directParameter` carries the
// command's direct object (the file path for encode/probe).
// ============================================================================

import Foundation

// MARK: - Argument helpers

private extension NSScriptCommand {

    /// The direct object as a trimmed string (the file path for encode/probe).
    var directString: String {
        (directParameter as? String) ?? ""
    }

    /// A named argument, tried under each candidate key (code and/or name),
    /// since `evaluatedArguments` keying varies across OSA dispatch paths.
    func stringArgument(_ keys: [String]) -> String {
        let args = evaluatedArguments ?? [:]
        for key in keys {
            if let value = args[key] as? String { return value }
        }
        return ""
    }
}

// MARK: - encode

/// `encode "<file>" using profile "<name>" to "<output>"` → job UUID or error.
@objc(MDYAEncodeCommand)
final class MDYAEncodeCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let file = directString
        let profile = stringArgument(["prof", "using profile", "profile"])
        let output = stringArgument(["outp", "to", "output"])
        return MainActor.assumeIsolated {
            ScriptingBridge.shared.encode(file: file, profile: profile, output: output)
        }
    }
}

// MARK: - probe

/// `probe "<file>"` → metadata JSON or error.
@objc(MDYAProbeCommand)
final class MDYAProbeCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let file = directString
        return MainActor.assumeIsolated {
            ScriptingBridge.shared.probe(file: file)
        }
    }
}

// MARK: - list profiles

/// `list profiles` → newline-separated profile names (matching the `.sdef`'s
/// declared `text` result), or an error string.
@objc(MDYAListProfilesCommand)
final class MDYAListProfilesCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            ScriptingBridge.shared.listProfiles().joined(separator: "\n")
        }
    }
}
