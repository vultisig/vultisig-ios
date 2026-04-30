# Defi Feature — Architecture & Improvement Plan

> Audit conducted 2026-04-30 after fixing the live-balance and stake-reset bugs (commit `99c7526b8`). Documents the current shape of the Defi feature, known pitfalls, and the staged refactor plan that this branch (`fix/defi-arch-improvements`) starts to execute.

## Layer map

```text
Views (SwiftUI, MainActor)
  DefiMainScreen / DefiChainMainScreen
  ↓ @ObservedObject Vault, @StateObject VMs
ViewModels (mostly @MainActor)
  Stake / Bond / LP / Main / ChainMain / SelectChain
  ↓ await interactor.fetch*(vault:)
Interactors (struct, protocol-backed)
  StakeInteractor • BondInteractor • LPsInteractor
    └─ THORChain… / MayaChain…
  DefiInteractorResolver — enum, static factory
  ↓ await save (crosses to MainActor)
Services
  DefiPositionsStorageService  (@MainActor; posts .defiPositionsDidChange)
  DefiBalanceService           (reads vault relationships)
  DefiPositionsService         (TokensStore-backed [CoinMeta])
  THORChainStakingService.shared / ThorchainService.shared / TokensStore
  ↓
SwiftData (@Model, MainActor-bound)
  Vault — @Relationship stake/bond/lp/defiPositions
  StakePosition • BondPosition • LPPosition • DefiPositions
```

## Known pitfalls

Severity legend: **CRIT** (correctness/data-race), **HIGH** (Swift 6 / fragile contract), **MED** (UX/maintainability), **LOW** (cosmetic). Status: ✅ resolved on PR #4274 / ⏳ open.

### Concurrency / actors

1. ✅ **HIGH** — `DefiChain/ViewModel/DefiChainBondViewModel.swift`: class missing `@MainActor`; only `refresh()` has it. *Resolved: class is now `@MainActor`.*
2. ⏳ **CRIT** — `DefiChain/Interactor/Stake/THORChainStakeInteractor.swift`, mirrored in Maya: `fetchStakePositions`/`createStakePosition` are not actor-isolated yet read `vault.coins`/`vault.defiPositions`/`vault.runeCoin` and (pre-DTO refactor) constructed `StakePosition(... vault:)` (a `@Model`, not `Sendable`). Works today by single-thread luck; will fail Swift 6 strict concurrency. *Partially resolved: the @Model construction is gone (DTOs); the input-side @Model property reads off MainActor remain. Tracked as the next testability win — ties into the THORChainStakingService protocol extraction.*
3. ✅ **MED** — `DefiChain/DefiChainMainScreen.swift`: `refresh()` awaited the four VMs sequentially. *Resolved: parallelized via `async let`.*
4. ⏳ **MED** — `DefiChain/Interactor/Bond/THORChainBondInteractor.swift:39-74`: per-node TaskGroup catches return `nil` and silently drop the failing node.
5. ⏳ **LOW** — implicit actor hop on `previousPosition`/`savePositions` (caller is non-MainActor; helper is `@MainActor`). Undocumented contract.

### `@Model` leakage

6. ✅ **CRIT** — `StakePosition.swift:35,60`, `LPPosition.swift`: `@Relationship(inverse:)` + `self.vault = vault` in `init` mutates `vault.<positions>` immediately on construction. The mechanism that produced Bug 2. *Resolved: interactors return DTOs; `@Model` instances are constructed only inside `DefiPositionsStorageService.upsert(...)` on `@MainActor`. The trap is dead.*
7. ✅ **HIGH** — Stake and LP interactors returned `[StakePosition]`/`[LPPosition]` (`@Model`s). *Resolved: replaced with `StakePositionData` / `LPPositionData` Sendable structs. Bond's `BondPositionDraft` pre-existed.*
8. ⏳ **MED** — `DefiPositionsStorageService` LP and Stake `upsert` only insert/update; never delete-stale. Bond `upsert` does. Asymmetry is undocumented.

### Error handling

9. ✅ **MED** — 7 `print(...)` calls in `DefiChain/Interactor/LPs/THORChainLPsInteractor.swift` and `MayaChainLPsInteractor.swift`. *Resolved: replaced with file-level `Logger`s.*
10. ✅ **MED** — LP fetch failure swallowed (`catch { print(...); return [] }`). *Resolved: `LPsInteractor.fetchLPPositions(vault:)` now `throws`; the VM catches and surfaces via `refreshError`.*
11. ✅ **MED** — `DefiChainBondViewModel.refresh()` logged on error but had no `@Published var error`. *Resolved: `refreshError` published on Bond + LP VMs, surfaced via `withBanner(text:style:)` toast on `DefiChainMainScreen`.*
12. ⏳ **LOW** — `DefiPositionsService.lpCoins()`: `(try? await thorchainService.getPools()) ?? []` — silent empty picker on transient network blip.

### Testability

13. ⏳ **CRIT** — Singletons (`Storage.shared`, `THORChainStakingService.shared`, `ThorchainService.shared`, `TokensStore`) and inline-constructed services (`THORChainAPIService()`) leave no DI seam. *Partially resolved: VMs accept `interactor:` and `storage:` via init, unblocking VM tests. Service-level singletons remain — tracked as the THORChainStakingService protocol extraction.*
14. ⏳ **HIGH** — `DefiInteractorResolver` is a static enum with no protocol. *Subsumed by direct VM-init injection; resolver protocol unnecessary for test seam.*
15. ⏳ **HIGH** — VM `init(vault: Vault, ...)` requires a SwiftData `@Model`; tests need a `ModelContainer`. *Mitigated: `DefiTestStore.makeInMemoryContainer()` test helper boots one in ~5 lines.*

## Refactor proposals

### (S) Surgical — ~3-4 hours, no signature changes
1. `print → Logger` in LP interactors.
2. `@MainActor` on `DefiChainBondViewModel` class.
3. Parallelize four-VM refresh with `async let`.
4. Add `@Published var error: String?` to Bond + LP VMs; surface via banner.
5. Bond TaskGroup: degraded fallback draft instead of dropped `nil`.
6. Document the `@MainActor` hop in `previousPosition`/`savePositions`.

### (M) Mid-scope — ~4 days, recommended
1. Add Sendable DTOs: `StakePositionData`, `LPPositionData` (Bond's `BondPositionDraft` already exists).
2. Interactor protocols return DTOs; storage service materializes `@Model` on `@MainActor`.
3. ViewModels publish DTO arrays. Views read DTOs (lookup `Coin` via VM).
4. Extract `DefiInteractorProviding` protocol; default-arg into VMs for DI seam.
5. Inject `Storage` and `NotificationCenter` into `DefiPositionsStorageService` for tests.

Side benefit: kills the inverse-relationship hazard from Pitfall #6 entirely (DTOs have no `vault` field, no SwiftData side effects on construction).

### (L) Large — Repository + UseCase, ~2 weeks
Match the Android shape (`DefiPositionRepository`, `Fetch*UseCase`). Domain types are pure values; persistence is an adapter. Defer until a third chain integration or offline-first behavior lands on the roadmap.

## Test plan (~35 tests)

| Layer | Count | Writability |
|---|---|---|
| `DefiBalanceService` (pure logic, takes `Vault`) | 6 | **today** with in-memory `ModelContainer` helper |
| `DefiPositionsStorageService` + notification spy | 6 | after (S) |
| ViewModels (Stake/Bond/LP/Main) — incl. Bug 1/2 regression tests | 12 | after (M) |
| Interactors (THOR + Maya × stake/bond/LP) | 14 | after (M) |
| Integration with in-memory `ModelContainer` | 3 | after (M) |

Tests we can't reasonably write as units: SwiftUI re-renders on `.defiPositionsDidChange` (XCUITest only), Swift 6 concurrency violations (compiler check, not runtime).

## Sequencing on this branch (`fix/defi-arch-improvements`)

1. (S) shortlist — 6 changes, no signature changes.
2. (M) DTO refactor — atomic; touches ~15 files.
3. Tests — write the writable-today suite first, then post-(M) suite.
4. Lint + build green; commit in logical chunks.

## Open questions

- LP/Stake `upsert` should align with Bond on delete-stale semantics — pending product call.
- `.defiPositionsDidChange` notification posts with `object: nil`. Should it carry the changed vault's `pubKeyECDSA` for multi-vault filtering? Moot today (single vault on screen).
- `DefiPositionsService.lpCoins()` swallow-and-return-empty: should the picker UI surface a refresh button on transient failure?
