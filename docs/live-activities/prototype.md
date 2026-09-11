# Transaction Live Activities

Live Activities start automatically for eligible broadcasts in all iOS build configurations, subject to the system Live Activities permission. No in-app enablement or amount setting is required. Transaction details follow the existing hidden-balances preference. Native macOS has no ActivityKit dependency.

This implementation uses **app-only updates**. In-process polling may stop when iOS suspends the app. Every nonterminal content state has a stale date 90 seconds after its last actual transaction observation. A healthy RPC lookup returning notFound supplies no newer transaction evidence, so the last positive observation timestamp remains unchanged and the update is shown as delayed. Stale data is never presented as a transaction failure. APNs registration, server watchers, token rotation, and suspended-device acceptance remain necessary for reliable updates while the app is suspended.

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

The link uses `vultisig://transaction/<local-record-uuid>`. ContentView queues it behind splash/passcode, drops it behind key-share recovery, then the detail destination resolves both the record and its vault locally. It does not depend on whichever vault is currently selected. Deleted records show an unavailable state. Opening a valid record refreshes the existing tracker/chain observer and receipt.

## Funds-free fixtures

For developer testing only, run an iOS DEBUG build with `-transactionLiveActivityDemo`. No vault is needed; no history row, network call or transfer is created. Optional flags:

- `-transactionLiveActivitySwap`: swap card with all rich receipt fields.
- `-transactionLiveActivityPrivate`: generic redacted payload.
- `-transactionLiveActivityStale`: observation timestamp already older than the 90-second stale threshold.

The demo requests a synthetic activity, updates after 8 seconds, and ends after 45 seconds while the process remains runnable. iOS suspension can delay those tasks, as with app-driven transaction updates. The fixture is available only through launch arguments; it has no settings entry. Synthetic IDs intentionally resolve to the unavailable-detail screen because they have no real history row. Known in-process fixture UUIDs are exempt from orphan reconciliation until the demo ends. After a process restart an abandoned fixture is removed normally.

The Lock Screen card fits within 160 points including padding; optional detail rows yield to the status, main amount and freshness when needed. The provider/fee/recipient/long-amount fixture should be included in simulator visual acceptance, with Island expanded/compact/minimal and stale/private states. Real locked-and-suspended delivery still requires signed-device/APNs validation.

## Contract and validation

`TransactionActivityState` is a Foundation-only Codable value. Its date encoding currently uses Swift JSONEncoder's default seconds-since-2001 strategy; future APNs envelope timestamps are Unix seconds and must not be confused with content dates. Keep the encoder/decoder strategy explicit in backend contract fixtures. Combined attributes + state are validated below 4096 bytes at request; every optional string has a scalar-wise UTF-8 bound, including pathological combining characters.

Unit tests cover privacy, byte budget, links, status/freshness semantics, lifecycle restoration/dismissal/limits/permission/deletion, full/partial provider refunds, receipt enrichment and durable storage notifications. Lifecycle tests inject a fake ActivityKit client, local lookup and no-op polling hook. The implementation agent runs generation/lint and local read-only cross-model review. The parent owns the full iOS test gate, macOS build and runtime acceptance; those must pass before any shipping claim.

## Branded card iteration

The card uses bundled token art only when the durable receipt contains an exact known local logo ID (BTC, ETH, USDC, USDT, BSC or Solana assets). Remote and unknown logos use a neutral asset glyph; a ticker never selects an image. Optional source/destination asset IDs are private-gated and backward-compatible with schema v1. No image data or URL enters ActivityKit.

The loading symbol makes one short pulse on fresh transaction observations, with no looping animation or invented progress. Reduce Motion, Always On luminance reduction, stale observations and terminal outcomes suppress processing motion. Status color distinguishes success, failure, refund and tracking end. The rich card falls back to its core header/hero/freshness layout within the 160-point Lock Screen budget.

Widget previews cover transfer, swap, private, delayed and failure. Synthetic runtime flags remain `-transactionLiveActivityDemo`, `-transactionLiveActivitySwap`, `-transactionLiveActivityPrivate`, and `-transactionLiveActivityStale`; add `-transactionLiveActivityFailure` for a failed terminal state after the normal 45-second fixture sequence. The fixture uses bundled USDC and ETH art and never sends funds.

## Testing automatic admission

Build and run this branch on iOS (Debug or Release). No preview toggle is needed. With system Live Activities allowed, an eligible outgoing send starts on the initiating/broadcasting device after a usable hash and saved receipt while the app is foreground. Signing-time max sends and other excluded payloads above remain ineligible. An already missed or dismissed transaction is not restarted. Up to two activities can be active; extra transactions stay in history. Hide balances to redact amounts and asset identity. Ordinary push-notification settings are separate.

Use the DEBUG launch fixtures for funds-free rendering checks. They bypass history because their IDs have no real receipt; coordinator regression tests separately verify automatic admission with fresh defaults, OS permission changes and hidden balances.
