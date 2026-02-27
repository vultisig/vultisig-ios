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

### Step 2: Build (only if lint passes)

```bash
xcodebuild -project VultisigApp/VultisigApp.xcodeproj \
    -scheme VultisigApp \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    build 2>&1 | tail -20
```

## Output

Report results clearly:
- **PASS** - Both lint and build succeed with zero warnings
- **LINT FAIL** - List SwiftLint warnings/errors to fix
- **BUILD FAIL** - List compilation errors to fix
