<!-- Copyright © 2026 MWBM Partners Ltd. All rights reserved. -->

# Running ConverterEngine tests locally, without `swift test`

**What this is:** a proven recipe for type-checking and actually **running** a
ConverterEngine XCTest file on the owner's Mac. It works even though `swift test`
can't run there: Xcode 27 is installed but not selected, and its licence isn't
accepted. It uses Xcode only by **file path**. It never uses `sudo`, `xcodebuild`
or `xcode-select`.

**Status:** first proven on 2026-09-25, for `AutoTagRunnerTests.swift` (#508
commit 4, `ddca8ab`). All 35 of its tests passed. Two planted faults made 11 tests
fail, so the harness genuinely detects breakage. **This is not `swift test`, and
CI remains the real test gate.** Report its results as "ran locally in a harness",
never as "tests pass".

This file is a how-to reference, not a handoff. Live status is in
`.claude/HANDOFF.md`.

## Set-up

```bash
REPO="<the repo root, or the worktree you are working in>"   # quote it: the path has spaces
H="<any scratch folder OUTSIDE the repository>"
P=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer
TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
mkdir -p "$H"; cd "$REPO"
```

The toolchain as found: `/usr/bin/swiftc` is Swift 6.4, and `xcode-select -p` is
still the Command Line Tools.

## 1. Build the engine (this produces the object file the harness links)

```bash
swift build --target ConverterEngine > "$H/build.log" 2>&1; echo "build exit=$?"
```

- **Pass condition:** exit 0. A "search path … CommandLineTools/…/Frameworks not
  found" linker warning is harmless.
- **Rebuild after EVERY source change.** The later steps link whatever object file
  is on disk, so a stale one silently tests old code.
- **The object file:** `.build/out/Products/Debug/ConverterEngine.o` is ONE merged
  arm64 object for the whole engine. The module interface is beside it. The ~207
  per-source `.o` files elsewhere are intermediates and are not used.
- **Scope:** this is the default build configuration only (no SUITE_CORE / DIRECT /
  APP_STORE variables).

## 2. Type-check the test file (quick; do it first)

```bash
swiftc -typecheck Tests/ConverterEngineTests/<TheTests>.swift \
  -I .build/out/Products/Debug -I "$P/usr/lib" -F "$P/Library/Frameworks" \
  -target arm64-apple-macosx15.0 -swift-version 6 -module-name ConverterEngineTests \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -plugin-path "$TC/usr/lib/swift/host/plugins" -plugin-path "$P/usr/lib/swift/host/plugins" \
  > "$H/typecheck.log" 2>&1; echo "typecheck exit=$?"
```

**Pass condition:** exit 0. `swiftc -parse` is NOT a substitute. It missed a
`@Sendable` closure mutating a captured `var`, which turned CI red on `d602cf0`.
This command rejects it.

## 3. Generate the runner (it must be named `main.swift`)

```bash
cat > "$H/main.swift" <<'EOF'
// Throwaway runner (scratch only, never committed).
import XCTest
let suite = AutoTagRunnerTests.defaultTestSuite   // ← the XCTestCase class to run
suite.run()
let result = suite.testRun!
print("HARNESS executed=\(result.executionCount) failures=\(result.totalFailureCount) unexpected=\(result.unexpectedExceptionCount) seconds=\(result.totalDuration)")
exit(result.totalFailureCount == 0 ? 0 : 1)
EOF
```

`defaultTestSuite` finds the `test_…` methods the way xctest does, and `async`
tests work. To run several classes, call each class's `defaultTestSuite.run()` and
add up the failures.

## 4. Compile and link the runner

```bash
swiftc -o "$H/harness" Tests/ConverterEngineTests/<TheTests>.swift "$H/main.swift" \
  .build/out/Products/Debug/ConverterEngine.o \
  -I .build/out/Products/Debug -I "$P/usr/lib" -F "$P/Library/Frameworks" \
  -L "$P/usr/lib" -lXCTestSwiftSupport -framework XCTest \
  -Xlinker -rpath -Xlinker "$P/usr/lib" -Xlinker -rpath -Xlinker "$P/Library/Frameworks" \
  -target arm64-apple-macosx15.0 -swift-version 6 -module-name ConverterEngineTests \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -plugin-path "$TC/usr/lib/swift/host/plugins" -plugin-path "$P/usr/lib/swift/host/plugins" \
  > "$H/link.log" 2>&1; echo "link exit=$?"
```

- **Pass condition:** exit 0 and an empty `link.log`.
- **XCTest at run time:** the two rpaths bake the Xcode folders into the binary, so
  no `DYLD_*` variables are needed.

## 5. Run it, and read the exit code directly (never through a pipe)

```bash
"$H/harness" > "$H/run.log" 2>&1; echo "run exit=$?"; grep HARNESS "$H/run.log"
```

## Optional checks

- **Rough parallel stress.** This is not the same as `swift test --parallel`:
  ```bash
  for i in 1 2 3 4 5 6 7 8; do ( "$H/harness" > "$H/par-$i.log" 2>&1; echo "run $i exit=$?" > "$H/par-$i.exit" ) & done; wait; cat "$H"/par-*.exit
  ```
- **Planted-fault check.**
  1. Back up the source and record its `shasum`.
  2. Plant a fault.
  3. Rebuild (step 1), relink (step 4), run (step 5): the run must FAIL.
  4. Restore the backup, confirm the checksum, then rebuild and rerun: the run must
     be green.

## Limits (what has and hasn't been tried)

1. **Proven for one engine test file only** (`AutoTagRunnerTests.swift`). Others
   should work the same way, but that is untested.
2. **Shared helpers.** A test file that uses helpers from another test file needs
   that file added to steps 2 and 4. Compiling the whole test folder at once hasn't
   been tried.
3. **`@testable import ConverterEngine` type-checks,** because the engine is built
   with testing enabled. Linking a test that uses internal members hasn't been
   tried.
4. **Resources.** ConverterEngineTests declares no resources. A test that needed
   bundled resources would not work as-is.
5. **App tests (`MeedyaConverterCoreTests`): NOT attempted,** and likely hard.
   `swift build` can't produce a MeedyaConverterCore object here: it stops at
   `actool`, and the native build system trips on SwiftUI macros. It would mean
   hand-compiling with `-emit-object`, a stub `Bundle.module` and the SwiftUI
   macro plugin path. The app-layer **type-check** recipe is in `.claude/HANDOFF.md`
   (search "A REAL local test-file type-check").
6. **CLI tests: not attempted.** They would need swift-argument-parser linked in.
7. **Not `swift test`.** One process, tests run one after another, and no xctest
   bundle or runner. **CI is the gate.**
