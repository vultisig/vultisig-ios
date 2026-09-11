# Transaction Live Activities

Live Activities start automatically for eligible broadcasts in all iOS build configurations, subject to the system Live Activities permission. No in-app enablement or amount setting is required. Transaction details follow the existing hidden-balances preference. Native macOS has no ActivityKit dependency.

This implementation uses **native-only, best-effort updates**, with no backend changes. On background entry, an existing eligible activity gets a UIKit background assertion for up to 25 seconds (less if iOS expires it), with an immediate observation and another every 10 seconds after the preceding observation completes. On each background entry, one BGAppRefresh request asks for a later single pass, no earlier than 15 minutes. Each delivered pass may request another while eligible work remains. iOS decides whether and when it runs; this is not a recurring timer or a guarantee of updates after suspension or force-quit. Disabling Background App Refresh or scheduler denial does not prevent the short UIKit continuation.

Every nonterminal content state has a stale date 90 seconds after its last actual transaction observation. A healthy RPC lookup returning notFound supplies no newer transaction evidence, so the last positive observation timestamp remains unchanged and the update is shown as delayed. Network errors, missing provider indexing and expiration never become transaction failure. Ordinary foreground tracking resumes when the app returns.

## Native background execution

The refresh path only observes recognized active records whose identity, vault, age, permission and durable status remain valid. It never creates or promotes an activity. Sends reuse the chain-status service; SwapKit swaps reuse provider tracking with a background observation mode that does not advance continuous-poller failure/give-up clocks. Source confirmation never means swap settlement. Identity and eligibility are checked again after network awaits, and cancellation discards late responses.

`TransactionActivityBackgroundRunner` owns exactly one window. Foreground entry, no remaining work, the 25-second deadline or OS expiration ends it. At 22 seconds the runner stops network observations and reserves the remaining three seconds for queued ActivityKit writes; OS expiration still releases runtime immediately. Generation-scoped cleanup prevents an older task from ending a replacement. Scheduled refresh performs one pass, waits for serialized ActivityKit writes during normal completion and reports completion exactly once. If the immediate UIKit window is already running, scheduled delivery preserves that window instead of replacing it. Expiration cancels work and releases runtime immediately without waiting for network cleanup. Pending requests are cancelled when no eligible activity remains; status events do not continually postpone the next request. Interrupted terminal writes can be recovered from the persisted terminal binding on the next reconciliation. Normal send polling resumes on foreground even if the activity was dismissed, and completed sends retain the wallet balance-refresh signal.

AppDelegate registers `com.vultisig.wallet.transaction-activity.refresh` before launch completes; the app plist declares that identifier and the `fetch` background mode. The app can receive a cold background launch without a scene, so the refresh core starts its own history-event subscription. SwiftData/keychain access can still be unavailable on a locked device; that fails closed and leaves honest stale content.

iOS 26 continued processing is intentionally not used: it presents system progress UI and expects measurable progress, which waiting for chain/provider settlement cannot reliably provide. This implementation supports the existing iOS 17 minimum. Apple's [background execution overview](https://developer.apple.com/videos/play/wwdc2025/227/) explains the system-controlled runtime and scheduling limits.

## Automatic coverage

- Starts on the initiating broadcaster after a successful usable hash and durable history row.
- Transfers proven by the signed-content decoder, plus conservative empty-memo EVM/UTXO sends built by the ordinary transfer builder. Raw signData, contract-call payloads, approvals, DeFi, QBTC claims, limit orders, amounts computed at signing (max-send), and skipped broadcasts are excluded.
- Market swaps carried by typed SwapKit payloads or generic payloads whose provider is SwapKit, with a supported SwapKit chain identifier. Native THORChain/Maya and other aggregators remain excluded from automatic activities.
- Swap source-chain confirmation is only `sourceConfirmed`. Provider settlement is separate: complete, full refund, partial refund, or authoritative failed/reverted. Retry exhaustion, parsing errors, replacement/dropped/unknown statuses and tracker outages remain delayed.
- No quoted destination amount is labelled as received. The rich swap summary shows the source amount and destination ticker. Fees, when available, remain explicitly estimates.
- Co-signer manual tracking, approval grouping, and the manual Track action for overflow are deferred. Extra transactions remain in history; they are not promoted automatically later.

## Lifecycle and privacy

The app persists an opaque-record binding and one-shot admission decision, keyed internally by a digest of vault + chain + hash. Dismissal, permission denial, request rejection, deletion and a two-active-card limit cannot cause a restart. On foreground, it reconciles system activities against saved bindings and history. Fetch errors preserve stale content; missing/deleted records or vaults end it. A crash in the request/persistence window may end the orphan rather than risk restarting it. Tracking ends at the next reconciliation after 7.5 hours, with the system's own maximum lifetime as the suspended-app backstop.

The existing history store uses vault + hash identity. Cross-chain hash collisions fail closed for activity admission and do not create an ambiguously mutable extra row. Migrating that history identity is outside this increment. Earlier broadcast rows accept missing fee/fiat enrichment from Done while preserving the original ID, status, tracker and existing nonempty receipt values.

Admission tombstones are retained indefinitely to preserve no-resurrection even across history resets/re-recording. A bounded migration/retention policy remains follow-up work. Existing admission decisions survive upgrades, including transactions already dismissed or rejected during the earlier preview.

All ActivityKit writes are serialized. Stale observations cannot overtake newer timestamps; terminal outcomes cannot regress. Privacy changes redact mutable payload data, including retained terminal cards. Hidden balances redact details both at admission and on subsequent privacy changes. Static attributes contain only the random local record UUID. Full recipient addresses are shortened inside the shared state initializer. Vault names, public keys, hashes, addresses in full, memos and signing material never enter the widget payload.

The link uses `vultisig://transaction/<local-record-uuid>`. ContentView queues it behind splash/passcode, drops it behind key-share recovery, then resolves both the record and its vault locally and opens the normal transaction-history details sheet. It does not depend on whichever vault is currently selected. Deleted records or vaults show the localized unavailable message through the existing app error presenter. Opening a valid record uses the history screen’s existing polling/tracking and receipt refresh. Dismissing the sheet returns to that vault’s transaction history.

## Contract and validation

`TransactionActivityState` is a Foundation-only Codable value. Its date encoding uses Swift JSONEncoder's default seconds-since-2001 strategy. There is no APNs contract in this native-only increment. Combined attributes + state are validated below 4096 bytes at request; every optional string has a scalar-wise UTF-8 bound, including pathological combining characters.

Unit tests cover privacy, byte budget, links, status/freshness semantics, lifecycle restoration/dismissal/limits/permission/deletion, full/partial provider refunds, receipt enrichment and durable storage notifications. Lifecycle tests inject a fake ActivityKit client, local lookup and no-op polling hook. The implementation agent runs generation/lint and local read-only cross-model review. The parent owns the full iOS test gate, macOS build and runtime acceptance; those must pass before any shipping claim.

## Branded card iteration

The card uses bundled token art only when the durable receipt contains an exact known local logo ID (BTC, ETH, USDC, USDT, BSC or Solana assets). Remote and unknown logos use a neutral asset glyph; a ticker never selects an image. Optional source/destination asset IDs are private-gated and backward-compatible with schema v1. No image data or URL enters ActivityKit.

The loading symbol makes one short pulse on fresh transaction observations, with no looping animation or invented progress. Reduce Motion, Always On luminance reduction, stale observations and terminal outcomes suppress processing motion. Status color distinguishes success, failure, refund and tracking end. The rich card falls back to its core header/hero/freshness layout within the 160-point Lock Screen budget.

Widget previews cover transfer, swap, private, delayed and failure states with bundled token art. The Lock Screen card fits within 160 points including padding; optional detail rows yield to status, amount and freshness. Real locked-device timing and automatic BGAppRefresh delivery require signed-device validation.

## Testing automatic admission

Build and run this branch on iOS (Debug or Release). No preview toggle is needed. With system Live Activities allowed, an eligible outgoing send starts on the initiating/broadcasting device after a usable hash and saved receipt while the app is foreground. Signing-time max sends and other excluded payloads above remain ineligible. An already missed or dismissed transaction is not restarted. Up to two activities can be active; extra transactions stay in history. Hide balances to redact amounts and asset identity. Ordinary push-notification settings are separate.

Use the widget previews for rendering checks. Coordinator regression tests verify automatic admission with fresh defaults, OS permission changes and hidden balances. The app has no synthetic activity launch mode.

## Testing native updates

Runner tests cover injected scheduled delivery, scheduler denial, expiration, foreground handoff, replacement races and exactly-once completion. Simulator may reject BGTaskScheduler submission, so do not interpret a manually invoked handler as proof of automatic scheduling.

On a signed device, make an eligible test transaction through the normal send/swap flow and immediately lock or background the app. Confirm the existing activity observes chain confirmation or provider settlement during the granted window. Also test slow settlement beyond that window, Background App Refresh disabled, offline recovery, app return, activity dismissal, vault/history deletion, two concurrent activities and force-quit. After the short window, delayed content is expected until iOS grants refresh or the app returns. No fixed update latency is promised.
