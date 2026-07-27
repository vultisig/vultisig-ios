## What & why

Closes #4955. Completes verification-to-surface on top of the phase-1 dynamic token catalog (#4954): the new dynamic breadth is reachable in the wallet **add-token** picker, gated so unverified tokens are only revealed by searching and are clearly flagged as a scam/impersonation risk.

**Stacked on #4954** — base `feat/dynamic-token-catalog-4941`; retarget to `main` once #4954 merges.

## Design — one unified, local-first pool

Both browse and search read the **same** catalog. Curated/local tokens are always present synchronously; provider tokens append when they load. There is **no opt-in toggle** — searching is the reveal.

- **Local-first ordering everywhere.** Held coins, then curated `TokensStore` presets, then provider breadth — deduped by `CoinMeta.uniqueId` (curated/local meta wins a collision).
- **Browse (empty query):** local + **verified** provider tokens (`.curated` + `.verified`). `.unverified` is NOT shown in browse.
- **Search (non-empty query):** filters the full pool (local + verified + `.unverified`), so typing reveals the badged unverified long-tail.
- **⚠ badge** kept on `.unverified` rows; **add-confirm** kept — adding an unverified token prompts a risk confirm listing each token's ticker + **full contract address**.
- **Spam hard-gate** (`CoinService.isLikelySpam`) applies to both the surfaceable and unverified lists — spam never appears, browse or search.

## Local-token search regression (fixed here)

Previously browse read `TokensStore` synchronously but search filtered only the async catalog result, and the load's `catch` never re-derived — so a curated/local token vanished from search while the provider fetch was pending or failed. The unified pool fixes it: the search pool always includes the presets, and the load **fails open** (surfaces the error for retry but still re-derives from local). Regression test: a curated Ethereum preset (AAVE) is found by search even when the injected provider fetch throws.

## Security posture

- **Unverified never auto-surfaces** — only revealed by an explicit search; browse shows curated/verified only. Held coins are matched to the catalog by `uniqueId` (not ticker), so an unverified lookalike sharing a held ticker (fake USDC on another contract) can't ride into the held/browse set.
- **Spam is a hard second gate** regardless of browse/search.
- **Enable/disable model unchanged** (`vault.coins` / `HiddenToken`); adds go through the normal `saveAssets`/`addToChain` path.
- **Swap pickers not regressed** — the wallet catalog is served via `loadCatalog` (a parallel `uniqueId → verification` map), deliberately not routed through `SwapTokenListCache`; the swap `loadTokens` path is byte-identical.

## Design details (no Figma yet)

- **Badge:** `triangle-warning` icon (12pt, `Theme.colors.alertWarning`) on a `bgSurface1` circle with a 2pt ring, top-trailing of the token tile, non-interactive. The 74pt grid cell can't fit a text pill, so the word "Unverified" lives in the badge a11y label + the add-confirm copy.
- **Confirm:** title "Add unverified token?", risk body, then `TICKER` + full contract per token.
- Screenshots: see below / attached.

## Verification

- **Gate**: `xcodebuild test` (iPhone 16 Pro Max, worktree-local DerivedData) → all suites pass except the sole allowed pre-existing artifact `CreateVaultSnapshotTests.testCreateVaultScreen_iPhone16Pro`. New suites `TokenSearchResultTests` + `TokenSelectionPoolTests` pass.
- **Cross-model review**: OpenAI Codex read-only per step + whole-branch. Findings fixed: (1) spam gated on both lists; (2) add-confirm shows the contract; (3) held-coin match by `uniqueId` so unverified lookalikes can't browse.

## Tests

- `searchResult` split (curated/verified vs unverified), spam hard-gated on both, verification map.
- `mergeLocalFirst` order/dedup (curated wins); browse = local + verified (no unverified) vs search reveals the badged unverified; held coins matched by `uniqueId` (lookalike excluded); curated token searchable + browsable when the provider fetch throws.

Flagging for **human + on-device (visual) review** of the badge/confirm and the browse-vs-search behavior.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
