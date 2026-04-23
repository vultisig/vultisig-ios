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
make build-check     # regenerate + compile (pipefail enabled, fails loudly)
make test            # builds + runs tests — prefer when test feedback is needed
```

`make build-check` is what the batch/agent automation uses — it runs `make generate` first, then `xcodebuild build` with `set -o pipefail` so a failed build doesn't silently pass due to the trailing `tail -20`.

For a custom destination or scheme, drop to `xcodebuild` directly (remember `set -o pipefail`):

```bash
set -o pipefail
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
