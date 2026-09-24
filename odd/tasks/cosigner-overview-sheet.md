# Co-signer overview sheet

## Objective

Replace transaction co-signer confirmation screens with the existing keysign overview sheet while preserving the payload-derived review and join/signing safety gates. Build on `feat/keysign-review-sheet-5421` at `9e1a581b9`. Do not push or open a PR until the user gives the green light.

## Scope and constraints

- Send, swap, and transaction-based DeFi/LP co-signer reviews on iOS and macOS.
- Review fields must derive from the received keysign payload, not initiator-only form models.
- Keep the existing committee-join and signing state machine, double-tap guard, fee readiness, Kamino refusal, and QR/relay behavior.
- Keep custom-message and QBTC claim flows on their existing specialized reviews until an overview design exists for them.
- Reuse the current blurred `crossPlatformSheet` style and existing overview visual components; no new sheet style.
- Strict TDD is enabled by project instructions: observe RED, GREEN, then REFACTOR using focused `xcodebuildmcp` tests. Run baseline SwiftLint before source edits.
- Delivery strategy: ask-on-risk; aim for reviewable work-unit commits, with tests alongside behavior. Approx. 400 authored changed lines is advisory, not a code-golf limit.
- Engram mirror pending if the memory tools remain unavailable.

## Tasks

- [x] **COS-6 — Stage co-signer review in Home.** Prepare the received QR payload concurrently with scanner dismissal, then animate the overview from a stable Home-owned sheet host only after both dismissal and review readiness. Remove the child sheet and 100 ms delay; keep direct deeplinks, macOS, specialized flows, and cancel/reopen safe. Route: delegated direct (Home/session view/test changes). Acceptance: handoff tests observed RED then GREEN; final focused iOS tests passed 19/19 and signing guards 11/11; macOS build, SwiftLint, and diff checks passed. Paired runtime UI remains unverified without a second-device fixture. Rollback boundary: Home handoff and sheet ownership, Join session injection, and focused assertions. Commit: `2c9e58fbb`.

- [x] **COS-5 — Present co-signer review after scanner dismissal.** Replace the QR scanner's fixed join delay with an actual sheet-dismissal handoff, so the native overview presentation animates only after the scanner is gone. Preserve direct deeplink and macOS entry, and ensure cancel/reopen cannot trigger a stale join. Route: delegated direct (scanner wrapper, Home state, focused tests). Acceptance: handoff tests observed RED then GREEN; 18/18 focused iOS tests, macOS build, SwiftLint, and diff checks passed. Rollback boundary: boolean sheet dismissal callback, Home scanner handoff, and focused assertions. Commit: `368d8fa40`.

- [x] **COS-4 — Remove co-signer Verify navigation.** Present the transaction overview from the scan origin without pushing `JoinKeysignView` behind it. Keep one live join session through review, committee waiting, signing, and completion; retain specialized custom-message/QBTC handling. Cover iOS scanner, deeplink, and macOS scanner entry points, dismissal, and retry. Route: delegated direct (multi-file navigation and state). Acceptance: focused navigation and repeated-status tests observed RED then GREEN; 19/19 focused iOS tests, macOS build, SwiftLint, and diff checks passed. Commit: `2d24f83d1`.

- [x] **COS-1 — Payload-backed review data.** Adapt Send and Swap overview content for received co-signer payloads; preserve fees, recipient, memo, min payout, and LP classification. Route: delegated direct (multi-file logic and tests). Acceptance: focused mapping tests failed before implementation (undefined adapter) and passed afterward (10/10 iOS simulator). Commit: `d8a7dd9af`.
- [x] **COS-2 — Join sheet and signing handoff.** Present the shared sheet locally in `JoinKeysignView`, wire Join confirmation and dismissal to existing state transitions, and retain safety gates. Route: delegated direct (multi-file navigation and tests). Acceptance: focused state test failed before implementation (missing `presentedKind`) and passed afterward (11/11 iOS simulator); macOS build passed. Commit: `1c5192179`.
- [x] **COS-3 — Scanner parity and verification.** Ensure loading/available/unavailable and risk verdict behavior is coherent for supported co-signer transaction types; run focused tests, lint, iOS/macOS builds and UI checks where feasible. Route: delegated direct (multi-file behavior and tests). Acceptance: focused tests failed before implementation (missing reset/verdict and unavailable-completion helpers), then passed. Commit: `8280f9acb`.

## Progress

- Isolated worktree and branch created from `9e1a581b9`.
- Baseline SwiftLint: 0 violations in 2,368 files.
- COS-1 RED: `xcodebuildmcp macos test --project-path VultisigApp/VultisigApp.xcodeproj --scheme VultisigApp --extra-args -only-testing:VultisigAppTests/JoinKeysignAmountFiatTests` failed at compile with missing adapter (expected); macOS test execution after implementation is unavailable because the runner cannot find the test product despite `TEST BUILD SUCCEEDED`.
- COS-1 GREEN: `xcodebuildmcp simulator test --project-path VultisigApp/VultisigApp.xcodeproj --scheme VultisigApp --simulator-id 157E1A0E-0272-43F8-A90E-8833C043F5BF --extra-args -only-testing:VultisigAppTests/JoinKeysignAmountFiatTests`: 10 passed, 0 failed.
- COS-1 runtime harness: N/A for pure summary mapping; sheet integration is COS-2. Rollback boundary: adapter and its focused assertions only.
- COS-2 GREEN: same focused iOS command, 11 passed, 0 failed after final sheet edit. `xcodebuildmcp macos build --project-path VultisigApp/VultisigApp.xcodeproj --scheme VultisigApp`: succeeded. Runtime UI harness remains pending because a paired signing fixture is unavailable. Rollback boundary: new join sheet, local Join presentation, and status test.
- COS-3 GREEN: same focused iOS command, 14 passed, 0 failed. Related `JoinKeysignDoubleTapGuardTests`, `JoinKeysignFailedStateGuardTests`, and `KeysignReviewScanRingTests`: 11 passed, 0 failed. Final SwiftLint: 0 violations. Final macOS build: succeeded. iOS test build succeeded. Scan reset invalidates an in-flight previous generation; unavailable scans complete and hide the ring; medium/high risk requires explicit acknowledgement before Join. Rollback boundary: scan lifecycle and risk policy helpers, sheet scanner integration, and focused assertions.
- UI runtime scenarios not exercised: live paired Send, Swap, and LP review; Blockaid transitions on a real received payload; sheet dismiss/reopen; Join failure/retry. A second-device/paired-vault fixture is not available in this worktree.
- COS-4 RED: `JoinKeysignAmountFiatTests` failed to compile first for missing `surface`, then for missing `newReviewKind` in the repeated-status regression. GREEN: 19/19 focused iOS simulator tests passed, including double-tap and failed-state guards. Final macOS build succeeded; final SwiftLint reported 0 violations; `git diff --check` passed.
- COS-4 navigation: Home owns a keyed Join session. The transaction overview appears over Home after scanner dismissal, while discovery, waiting, signing, and done use the full Home-sized host with the same view models. Mac scanning returns to Home before opening the session; custom-message and QBTC states retain their specialized surfaces. Closing the overview without joining removes the host; rescanning creates a fresh session. Repeat `.JoinKeysign` publications cannot reset the scan or reopen a dismissed review.
- COS-4 runtime harness: live paired signing was not exercised because no paired-vault/second-device fixture is available. Rollback boundary: Home session host and pending Mac request, Join review/session presentation, removed Join navigation route, and focused assertions.
- Authored diff against `9e1a581b9` is 442 application/test lines plus this recovery document (482 lines before final receipt update), over the advisory 400-line budget. PR slicing is deferred until user approves PR work.
- To recover disk space, XcodeBuildMCP purged exactly three test-products bundles generated by this worktree's tests (8.44 GB); source and caches were untouched.
- PR and push withheld pending explicit user approval.
- COS-5 baseline SwiftLint: 0 violations in 2,370 files. RED: focused iOS test compilation failed because `ScannerKeysignHandoff` did not exist. GREEN: the final `JoinKeysignAmountFiatTests` run passed 18/18 on iOS Simulator; macOS build succeeded; final SwiftLint had 0 violations; `git diff --check` passed.
- COS-5 handoff: a decoded keysign QR stays pending through the scanner's native `onDismiss` callback; only then is the Home co-signer session mounted and its overview sheet animated. Cancel does not join, and a new scanner presentation invalidates the previous handoff. Direct deeplinks and the macOS scanner route remain immediate. Live QR-to-overview animation was not exercised without a paired signing fixture.
- COS-6 baseline SwiftLint: 0 violations in 2,370 files. RED: focused iOS test compilation failed because `ScannerKeysignHandoff.reviewReady()` was absent. GREEN: final focused simulator tests passed 19/19; signing guard and scan-ring suite passed 11/11; final macOS build succeeded; SwiftLint and `git diff --check` passed.
- COS-6 presentation: Home now owns the review sheet and one stable Join model/delegate for payload preparation and signing. Preparation starts as the scanner dismisses; the handoff gate permits overview presentation only after both payload readiness and native `onDismiss`. The child view's 100 ms delay and nested sheet are gone. Scanner-origin preparation masks the transient child spinner, with an explicit loading backdrop only if decoding outlasts dismissal. Camera scans self-dismiss; the iOS-on-Mac importer and external links close explicitly. A new scan clears the old pending session and ID-guards late callbacks. Specialized custom-message/QBTC/nonrelay session states still use the full-screen host. Live paired QR-to-overview animation was not exercised because no paired fixture is available.

## Next step

Await user approval for PR creation. Before PR work, exercise the paired runtime scenarios above, including the QR-to-overview animation, and decide the PR slicing strategy with the user.
