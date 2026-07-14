# Figma reference exports (local-only)

This directory holds the source-of-truth Figma exports the parity tests diff against.
They are **gitignored** (`*.png`) — heavy binaries that go stale — so on a fresh
checkout the directory contains only this README (plus the one committed self-test
PNG below) and any parity test whose reference is absent **skips** rather than fails.

## Committed exception: `selftest-fixture.png`

The single committed PNG is **not a Figma export**. It is a render of the test-only
fixture view in `../FigmaParitySelfTests.swift`, produced by the harness's own
renderer, and it exists so the comparator's mechanics (perceptual gate, degradation
scoring, `bestAlign` offset recovery) are exercised on every CI run instead of
shipping as dead code. The fixture is text-free so cross-machine font antialiasing
cannot flake it.

To regenerate it (e.g. after changing the fixture view):

```sh
cd VultisigApp
TEST_RUNNER_FIGMA_PARITY_RECORD=1 xcodebuild test \
  -project VultisigApp.xcodeproj -scheme VultisigApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
  -only-testing:VultisigAppTests/FigmaParitySelfTests/testRecordSelfTestReference
```

The record run writes the PNG here and then **fails on purpose** (so a record run is
never mistaken for a green suite). Inspect the image visually, commit it, and re-run
the suite without the env var — all self-tests should pass.

## Adding references for a real screen

Export each frame from Figma at the frame's point size **× 3** (device @3x) and save
it here as `<reference-name>.png`, where `<reference-name>` matches the `reference:`
string passed to `assertFigmaParity` in your test. Export via the Figma MCP:
`download_assets(fileKey, nodeId, format: "png", defaultScale: 3)`.

Keep real Figma exports out of git (the `*.png` ignore already handles it): they are
multi-megabyte and rot as the design evolves. The tests skipping when a reference is
absent is the intended behavior for fresh checkouts and CI.

## Keeping them outside the repo

Set `FIGMA_PARITY_REFS=/absolute/path` to read references from any local directory
instead of this one (e.g. a shared design-exports folder). `FIGMA_PARITY_OUT` likewise
redirects the `.actual.png` / `.diff.png` output that normally lands in `../__Output__/`.
