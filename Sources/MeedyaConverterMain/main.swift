// ============================================================================
// MeedyaConverter — executable entry point
// Copyright © 2026 MWBM Partners Ltd. All rights reserved.
// ============================================================================
//
// This is the entire runnable executable target. All application code lives in
// the `MeedyaConverterCore` LIBRARY target so that it can be unit-tested via
// `@testable import MeedyaConverterCore` (SwiftPM cannot `@testable import` an
// executable target). This file exists solely to launch the SwiftUI app, the
// job the `@main` attribute used to do before the split.
// ============================================================================

import MeedyaConverterCore

MeedyaConverterApp.main()
