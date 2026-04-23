---
name: build-check
description: Run SwiftLint and xcodebuild to verify the project compiles cleanly.
disable-model-invocation: true
---

# Build Check

Full quality check: lint first, then build.

## Steps

### Step 1: SwiftLint

```bash
swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/
```

If lint fails, fix all warnings before proceeding to build.

### Step 2: Regenerate the project (only if the source tree changed)

If `project.yml` was edited or Swift files were added/removed/renamed since the last generate, run:

```bash
make generate
```

### Step 3: Build (only if lint passes)

Prefer the Makefile target when the scheme + destination match the default:

```bash
make test    # builds + runs tests
```

For a compile-only check without running tests, fall through to `xcodebuild`:

```bash
cd VultisigApp && xcodebuild build \
    -project VultisigApp.xcodeproj \
    -scheme VultisigApp \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -skipPackagePluginValidation 2>&1 | tail -20
```

## Output

Report results clearly:
- **PASS** - Both lint and build succeed with zero warnings
- **LINT FAIL** - List SwiftLint warnings/errors to fix
- **BUILD FAIL** - List compilation errors to fix
