---
name: make
description: Use the Makefile at repo root for bootstrap, project regeneration, unit tests, and UI tests. Use when asked to build, test, bootstrap the workspace, or regenerate the Xcode project.
---

# Make

All common dev commands are defined in the `Makefile` at the repo root. Prefer these over raw `xcodebuild` or `xcodegen` invocations — they keep CI, local dev, and contributor instructions consistent.

## Commands

| Command | Purpose |
|---|---|
| `make bootstrap` | First-time setup. Installs XcodeGen + SwiftLint via Homebrew and generates `VultisigApp.xcodeproj`. Safe to re-run — it's idempotent. |
| `make generate` | Regenerate the Xcode project after editing `VultisigApp/project.yml`, adding/removing/renaming Swift files, or pulling changes from `main`. |
| `make test` | Run the unit-test suite on iOS Simulator via the `VultisigApp` scheme. |
| `make ui_test` | Run UI tests on iOS Simulator via the `VultisigAppUITests` scheme. |
| `make help` | List all targets. |

## When to use each

- **After cloning the repo:** `make bootstrap`.
- **After `git pull` that touched `project.yml`** or after you added/renamed/removed Swift files: `make generate`.
- **Before opening a PR:** `make test`.
- **After touching UI flow tests:** `make ui_test`.

## Overrides

Override the simulator, scheme, or both via environment variables:

```bash
make test DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
make test APP_SCHEME=VultisigApp
make ui_test UI_SCHEME=VultisigAppUITests
```

Defaults: `DESTINATION = platform=iOS Simulator,name=iPhone 17 Pro Max`, `APP_SCHEME = VultisigApp`, `UI_SCHEME = VultisigAppUITests`.

## Do not

- **Do not edit `VultisigApp/VultisigApp.xcodeproj/project.pbxproj`.** It is generated. Edits will be overwritten on the next `make generate`.
- **Do not add files to the Xcode project through Xcode's UI.** Create them on disk under `VultisigApp/VultisigApp/` and run `make generate` — XcodeGen auto-discovers sources.
- **Do not invoke `xcodegen` or `xcodebuild` directly for routine tasks** when a `make` target exists.

## Related

- Project spec: `VultisigApp/project.yml`
- XcodeGen docs: <https://github.com/yonaskolb/XcodeGen>
- Other skills: `/build-check` and `/lint` use the Makefile targets where applicable.
