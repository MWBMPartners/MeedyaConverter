// ============================================================================
// MeedyaConverter — SuiteCoreBridge
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution
// of this file, via any medium, is strictly prohibited.
// ============================================================================
//
// Thin bridge layer between MeedyaConverter and the MeedyaSuite-core Rust
// workspace (via Swift/C FFI bindings). When the `SUITE_CORE` compilation
// flag is enabled, this file forwards calls to the `MeedyaCore` Swift module
// published by `MWBMPartners/MeedyaSuite-core`. When the flag is absent the
// bridge compiles as a set of no-op stubs so the rest of the codebase can
// treat MeedyaSuite-core integration as optional.
//
// GitHub Issue #373 — Add MeedyaSuite-core Swift Package dependency.
// ============================================================================

import Foundation

#if SUITE_CORE
@_implementationOnly import MeedyaCore
#endif

// MARK: - SuiteCoreAvailability

/// Runtime availability flag for MeedyaSuite-core.
///
/// Callers can check this before attempting to use suite-core APIs to decide
/// whether to fall back to the inline MeedyaConverter implementations.
public enum SuiteCoreAvailability: Sendable {
    /// Whether the MeedyaSuite-core Swift bindings are linked into this build.
    public static var isAvailable: Bool {
        #if SUITE_CORE
        return true
        #else
        return false
        #endif
    }

    /// The compile-time version of the MeedyaSuite-core module that this
    /// binary was linked against. Returns `nil` when the suite-core bindings
    /// are not available.
    public static var linkedVersion: String? {
        #if SUITE_CORE
        return MeedyaCore.MeedyaCoreVersion.string
        #else
        return nil
        #endif
    }
}

// MARK: - SuiteCoreBridgeError

/// Errors produced by the suite-core bridge when the expected API surface is
/// unavailable (e.g., the build was produced without `SUITE_CORE=1`).
public enum SuiteCoreBridgeError: Error, Sendable, LocalizedError {
    /// Raised when a suite-core API is called in a build that did not include
    /// the MeedyaSuite-core dependency.
    case notCompiledIn

    /// Raised when the FFI call returned a null pointer or an unrecognised
    /// error code that cannot be mapped to a higher-level error.
    case unknownFailure(String)

    public var errorDescription: String? {
        switch self {
        case .notCompiledIn:
            return "MeedyaSuite-core was not linked into this build. "
                 + "Rebuild with SUITE_CORE=1 to enable this feature."
        case .unknownFailure(let detail):
            return "MeedyaSuite-core bridge error: \(detail)"
        }
    }
}

// MARK: - SuiteCoreSmokeTest

/// Smoke test entry point exercising a single MeedyaSuite-core API.
///
/// The acceptance criteria for issue #373 require that at least one
/// `meedya-core` API be callable from Swift. This struct exposes exactly one
/// such call so CI can assert the bridge is wired up correctly.
public enum SuiteCoreSmokeTest: Sendable {

    /// Invokes the suite-core "ping" API and returns the advertised version
    /// string. Throws ``SuiteCoreBridgeError/notCompiledIn`` when the build
    /// did not include the suite-core dependency.
    public static func ping() throws -> String {
        #if SUITE_CORE
        return MeedyaCore.ping()
        #else
        throw SuiteCoreBridgeError.notCompiledIn
        #endif
    }
}
