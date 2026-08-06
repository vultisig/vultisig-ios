# Invariants and traps

Everything on this page exists because a review caught a real fund-loss bug, or
because a plausible-looking cleanup was proposed and rejected with a reason. If
you are about to change something here, find it below first.

## Rule zero

> A key share that cannot be opened is one this device can never sign with
> again. There is no server copy and no support ticket that fixes it — recovery
> depends entirely on the user having a `.vult` backup, or on the vault's other
> signers still reaching its threshold without this device.

`Vault.getThreshold()` is `ceil(signers × 2/3) − 1`, so a share loss is not
automatically fatal to the vault — but it is entirely outside this code's
control whether it is. Treat "the share becomes unopenable" as unrecoverable
here, because from inside `Core/Security/` it is.

Every guard in `Core/Security/Keyshare/` is there to make a specific unopenable
state unreachable. "This check looks redundant" is almost always the sound of a
state you have not thought of yet.

---

## The three sweeper refusals

`KeyshareSweeper` is the only thing in the feature that rewrites key material in
bulk. It refuses three things, and each refusal is a bug that shipped in a draft.

### 1. Two phases — never apply per vault

Everything is computed and verified in memory before a single model is touched;
the writes go in together only once every share in every vault has passed.

Applying a vault as soon as it verifies leaves earlier vaults mutated in the
**live** context when a later one fails — and an unrelated autosave can flush
that half-swept state to disk. Autosave is on by default, which is why the sweep
disables it for the duration and restores it after.

Two companions to this rule, equally load-bearing:

- **whole-array assignment.** `vault.keyshares = newArray`, never
  `keyshares[i] = …`. Assigning into an element is not a dependable way to mark a
  `@Model` dirty, and a sweep that reports success while persisting nothing
  leaves plaintext shares sitting behind a passcode.
- **explicit `save()`, and `rollback()` if it throws**, so the context cannot
  carry a partial sweep forward.

### 2. Authenticate every already-sealed value

`KeyshareProtector.seal` returns an already-sealed value **unchanged and
unchecked**. A sweep that takes that on trust reports success over a share sealed
under a key nobody holds any more — a dead vault, and nothing ever revisits it
*because the sweep said it was fine*.

So `sealAll` opens every already-sealed value it meets. Symmetrically, it
**asserts its own output is sealed**: with no key in hand `seal` returns the
plaintext unchanged, so without that check a sweep with nothing to seal with
would report success over shares it left in the clear.

This is why the protocol has no `hasPlaintextShares() -> Bool`. A `Bool` cannot
carry "one of these does not authenticate", and a caller that got `false` would
proceed.

### 3. Refuse a value that opens to *another* sealed value

Only the outermost envelope used to be opened. A value shaped like
`seal(seal(share))` authenticates on its outer layer, so `sealAll` accepted it
unchanged and `unsealAll` wrote the **inner `vlt2:` string** back and reported
the store fully unsealed. The disable that follows then deletes the key, and what
is left cannot be opened by anything, ever.

The app cannot construct one — `seal` refuses an already-sealed value — but an
imported `.vult` or JSON backup can carry whatever bytes it likes. Both the
sweeper's `openedShare(from:)` and `KeyshareNormalizer.opened(_:pubkey:)` — the
route every import takes in, shared with the keygen commit — open once and
**refuse** a result that is still sealed.

**Do not "fix" this by unwrapping recursively.** Recursion accepts adversarial
input rather than rejecting it. One layer is the most a legitimate backup can
carry: the export path (`Vault.mapToProtobuff`) writes opened plaintext, and the
import path will not wrap an already-sealed value.

### And: the context must be clean

A dirty main `ModelContext` is `KeyshareSweeperError.busy`, surfaced as
`PasscodeError.busy`, and the user retries.

Two alternatives were proposed and both rejected:

- **flush foreign pending changes** (`if hasChanges { save() }`) — commits
  somebody's half-finished keygen, reshare or import merely because the user
  enabled a passcode. Some code defers persistence deliberately until a flow is
  confirmed; rolling them back instead would throw that work away. Neither is the
  sweeper's to decide.
- **use a dedicated context off the same container** — the main context would
  keep stale `Vault` objects holding the old plaintext, and a later edit to one
  of those writes it back.

`hasSealedShare()` refuses a dirty context too, for a sharper reason — see
[transitions](transitions.md#step-4-never-mint-over-evidence).

---

## Ordering constraints — do not reorder these

| Constraint | Reordering it produces |
|---|---|
| the wrapper is durable **before** anything is sealed | every sealed share orphaned by a crash, key never having left memory |
| `mode = .passcode` fires **the moment the wrapper verifies**, not after the sweep | a passcode both durable and unreachable: no gate, so no unlock, so no resume, and retry says `.alreadySet` |
| a failed sweep does **not** delete the wrapper | already-sealed shares stranded; a later set mints a *different* key that opens none of them |
| disable changes the mode **before** deleting the wrapper | plaintext shares behind a gate with nothing to unlock against |
| disable removes the biometric copy **before** any share moves | a survivor silently works again next time a passcode is set; and a failure after the shares moved reports an error over a half-gone passcode |
| the wrapper is re-stored **before** anything is resealed in the disable rollback | ciphertext whose only key is in memory, destroyed by the next lock |
| `session.currentGeneration` is captured as the **first instruction** of `setPasscode` and `unlock` | a background `lock()` silently undone; the key stays live behind a lock screen |
| reconciliation runs **synchronously first** inside `restorePasscodeLockOnLaunch` | the gate chosen from a mode reconciliation is about to change; app sits open all session with a wrapped key and no lock screen |
| `prepare:` in `ProtectedVaultImporter.commit` runs **after** the save, inside the lease | a preparation whose own save fails could no longer be taken back. `rollback()` undoes it there *only* because the insert's save has already flushed whatever the context was carrying and nothing suspends in between, so everything still pending is provably `prepare`'s — see [below](#the-write-that-did-not-take). Ahead of that save the same call would discard another flow's uncommitted work, `commit` cannot enumerate what an arbitrary `prepare` wrote in order to withdraw it row by row, and leaving it pending reaches disk anyway through the next autosave or any unrelated `save()` |

---

## The write that did not take

A user reported imported vaults arriving with no chains at all. Every save along
the way had succeeded. Two rules came out of it, and both are easy to undo by
accident because neither failure raises anything.

### Attach a coin from the coin's side

`coin.vault = vault`, **never** `vault.coins.append(coin)`.

On a `Vault` that has already been through a `context.save()`, appending a still
unsaved `Coin` to the to-many side does not register. The relationship re-faults
to its persisted value, and the next save writes that value back **over** the
`Coin.vault` inverse the append had just set. What lands on disk is coin rows
belonging to nobody and a vault with no chains — nothing thrown, nothing logged,
and a wallet that simply opens empty.

The to-one write is the one that survives, and on a vault that has not been
inserted yet it does exactly what the append did — which is why it is correct
for both callers. `VaultDefaultCoinService` also detaches from that side
(`coin.vault = nil`) before deleting a coin it is taking back, for the same
reason. `CoinService.addToChain` sidesteps the trap differently, by saving the
coin before appending; there is no save to hang that on inside the preparation.

Keygen never hit this — `commitVault` prepares a vault it has not inserted yet.
The import path prepares after insert + save, for the ordering reason above, so
it is the caller that reaches the trap.

### `prepare`'s success is a postcondition, not a `catch`

`prepare` answers `Bool` and `commit` **checks the answer**, in addition to
catching a throwing save. That is the whole point: in the failure above the save
*succeeded* and stored nothing, so an error-only guard saw a clean import and
said nothing. And nothing rebuilds what the preparation writes **automatically**
— default coins are set at keygen and at import and nowhere else — so a vault
that leaves `commit` unprepared is one the user opens missing chains, with no
error, indefinitely. Manage Chains can add one back by hand, but only for a
vault type that allows it (`Vault.canCustomizeChains` is false for key-import
vaults) and only by a user who has worked out that something is missing, which
nothing tells them.

An unprepared vault is put through the idempotent preparation once more, and
reported if it is still unprepared. It is not thrown: the vault is stored and
openable, and refusing an import that already reached disk would leave the user a
vault they can no longer re-import.

The answer is only worth checking if it stays truthful, and two ways of
computing it were not:

- **read off what succeeded, the answer holds vacuously.** A postcondition checked
  against the coins that *built* is satisfied by an empty list — the vault with
  no chains at all passes as prepared, which is the reported symptom surviving
  its own fix. It is read off the chains the vault was asked for instead, minus
  the ones the catalog carries no native asset for at all. That subtraction is
  logged rather than silently filtered: a chain with nothing to build (there is
  one, `ethereumSepolia`, offered in the key-import picker) is a gap in this app;
  a chain that failed to build is a broken key. Only the second is a failure to
  report, and reporting the first would mark every such import broken forever
  with nothing a user or a retry could do.
- **a vault that already holds coins must not be blessed.** Skipping the *work*
  for one is right; answering `true` for it is not. The retry lands exactly
  there — first pass a chain short, second pass sees one coin and calls the
  import clean — so the reporting the postcondition exists for reports nothing.

`prepare` must also **start nothing that outlives it**. Token discovery is the
case that exists: it suspends on the network and then writes through
`Storage.shared`, so started from inside the preparation it can come back and
persist a vault whose save failed and which the caller has already withdrawn.
The preparation therefore records value identifiers only — a vault's public key
and a coin id — and the caller starts `startTokenDiscovery()` afterwards: keygen
once its own save has landed, the import once `commit` has returned.

`commit` returning is **not** proof that the preparation's save landed — it
returns normally after a preparation that failed twice and was rolled back — so
the identifiers are what makes that safe rather than the ordering. Each coin is
looked up again through its vault immediately before its own discovery runs, and
one the store no longer holds that way is skipped. Hand a live `Coin` or `Vault`
across that gap instead and the rolled-back case is not a skipped lookup but a
detached model, which traps on the first property read.

---

## Fail closed, and which direction that is per site

"Fail closed" is not one direction — it depends on which mistake loses key
material at that call site. `KeychainReadResult` is three-valued
(`absent` / `present` / `unavailable`) precisely so each site chooses
explicitly, and the deliberate collapses all go through the conspicuously named
`valueTreatingUnavailableAsAbsent` so no consumer collapses invisibly.

| Site | `.unavailable` is read as | Because the opposite would |
|---|---|---|
| `PasscodeService.isSet` | **set** | let `setPasscode` mint a fresh key **over** an existing wrapper; the new key opens no share the old one sealed |
| `KeyshareKeySession.currentState()` | **`.locked`** | make `.disabled` a licence to write plaintext behind a live passcode |
| `PasscodeService.unlock` | `.storageFailure` | `.notSet` sends the UI off to offer *creating* a passcode over one that exists |
| `unlockWithBiometrics`' wrapper read | `.storageFailure` | leave nothing to check the bound copy against |
| `storeWrappedDataKey` read-back | **write failed** | record an unverified write as durable, then seal against it |
| `deleteWrappedDataKey` read-back | **delete failed** | record a removal as done and never retry it |
| reconciler: store occupancy | **defer the clear**, marker unset (alignment still runs) | set a permanent marker on a guess, keeping a previous install's wrapper forever |
| reconciler: inherited material | **defer the clear**, marker unset (alignment still runs) | issue launch-time Keychain deletes on a first-ever install whose Keychain stuttered |
| reconciler: lock-mode alignment | **move nothing** | raise a gate with nothing behind it, or take a real gate down |
| `isPasscodeGateRequired` — every overlay decision | **gate required** | take a real lock screen down over a Keychain that merely went quiet |
| `PasscodeAttemptLimiter.loadState` | **no record** ← the one exception | put a permanent, undecayable lockout in front of a passcode the user knows |

That last row is the deliberate exception and it is argued at the call site.
`remainingLockout` would answer an unreadable state with a flat maximum delay
that never decays and that a correct passcode cannot clear — clearing needs a
write the same Keychain is refusing. The strict reading also buys nothing:
anyone able to make the item unreadable can **delete** it instead, and a deleted
item is `.absent`, which is legitimately a fresh start. A *corrupt* record still
fails closed. If you revisit the limiter, re-read that paragraph before changing
it.

### The optional-promotion trap

A `KeychainReadResult` is **not** an `Optional`, but Swift will happily compare
one to `nil` via optional promotion — and the comparison is then always false.
That shipped once: a guard in `KeyshareInstallReconciler` became permanently
false, so the destructive clear repeated **on every launch**, silently removing
any passcode set after the first one. It compiled green and the whole suite
passed.

If you write `someKeychainRead == nil`, you have written a bug. Use
`valueTreatingUnavailableAsAbsent == nil` when the collapse is what you mean, or
switch over the cases.

---

## Things that look like safe cleanups and are not

| Tempting change | Why not |
|---|---|
| make `KeyshareWriteCoordinator` an `actor` or `@MainActor` | its hottest caller is a **synchronous** TSS callback on an arbitrary thread. A `Task` hop loses the atomicity that is the entire point; `DispatchQueue.main.sync` deadlocks when the callback is already on main |
| have the app unlock take a `TransitionLease` like the other operations | transitions are refused while a keygen episode is open, and keygen holds one through the deferred "Looks Good" commit — an app that auto-locked on the review screen could **never be opened again** |
| add an acquiring `resumeSweep()` for API completeness | a lease is not reentrant; it would throw `.busy` on the one path that must always work |
| make `lock()` synchronize with the actor to close the last one-instruction race | a background lock must never block on a transition. The window is accepted and documented |
| move the `session.currentGeneration` read below a "cheap" guard | that is exactly the bug that let a `lock()` be undone during the sealed-share scan |
| unwrap doubly-sealed values recursively instead of refusing them | accepts adversarial input rather than rejecting it |
| have the sweeper flush or roll back a dirty context so it can proceed | commits or discards another flow's half-finished work because the user toggled a setting |
| attach a vault's default coins with `vault.coins.append(coin)` instead of `coin.vault = vault` | on a vault that has already been saved the append does not register: the relationship re-faults and the next save writes the empty value back over the inverse, so the coin rows end up belonging to nobody and the vault opens with no chains — silently, and every save reports success. See [above](#attach-a-coin-from-the-coins-side) |
| let `prepare:` report success by not throwing, now that `commit` catches its save | the failure that shipped was a save that *succeeded* and stored nothing, which no `catch` can see. See [above](#prepares-success-is-a-postcondition-not-a-catch) |
| replace `KeyshareSweeping`'s per-method `@MainActor` with an attribute on the protocol | attributing the protocol infers main-actor isolation onto the whole conforming type, singleton included — and an `actor` cannot name a main-actor singleton as a default argument. Same reason on `ProtectedVaultImporter` |
| make `KeyshareSweeping` `Sendable` | cascades into `KeyshareProtecting`, whose implementation holds a non-`@Sendable` closure. A Swift 6 migration item, not a local cleanup |
| clear `lastMigratedVersion` in the reconciler | re-runs every ordinary migration on a container with no passcode artifact — a launch-time write for people who never touched this feature |
| delete the plaintext passthrough in `open` / `seal` now that encryption exists | `.disabled` is permanent and the majority state. Both passthroughs are forever |
| let `BiometricKeychain.store` delete-then-add in one place with one query | `SecItemDelete` takes a *search* query; the full add dictionary matches nothing and the add answers `errSecDuplicateItem`, silently breaking rebinding after a passcode change |
| collapse `BiometricUnlockError.malformedCopy` into `.failed` | `.failed` also covers "the face did not match", which the UI stays silent about — so a *successful* Face ID would appear to do nothing while silently disabling the shortcut |
| have `KeyshareInstallReconciler` skip taking the transition lease (it only runs at launch) | a launch landing between `setPasscode` verifying its wrapper and adopting the key deletes that wrapper **and marks the container done** |
| raise or lower the overlay from `AppLockService.mode` instead of `isPasscodeGateRequired` | the mode is `UserDefaults` and the wrapper is Keychain; a completed disable moves them at different moments. Reading the mode leaves a lock screen standing with nothing that can dismiss it — see [transitions](transitions.md#the-gate-is-derived-never-cached) |
| cache the gate predicate in a `@Published` flag and update it on transitions | the transitions that matter run while the overlay is already up, from a `nonisolated` `lock()` that synchronizes with nothing. Re-deriving is the only shape that cannot go stale |
| wire the lock screen to `PasscodeService.unlock(with:)` | see below — there is **no compile-time forcing function** for this one |

### The one with no forcing function

`unlock(with:)` and `unlockApp(with:)` take the same argument, throw the same
errors, and compile identically at the lock screen's call site. `unlock` is
passcode *verification*: no lease, no resume sweep. Wired to it, the lock screen
looks and behaves exactly right while **silently never finishing an interrupted
transition** — so shares an interrupted `setPasscode` did not reach stay in the
clear behind a live passcode for as long as the app is installed.

This actually happened during a rebase that was textually clean and compiled.
`PasscodeViewModel.unlock()` carries a doc comment saying it must stay on
`unlockApp`; the change flow's own `service.unlock(with: current)` is correct and
must stay as it is.

A protocol seam that would let a test prove which method the lock screen reaches
was proposed and rejected: `PasscodeService` is an `actor` whose methods carry
`now: Date = Date()` defaults and `@discardableResult` returns, so the protocol
needs renamed shim requirements to dodge overload ambiguity — roughly sixty lines
of indirection plus a mock, to guard one line.

Contrast the forcing function that *does* exist: `PasscodeError` is switched
exhaustively in the view model's message mapping, so adding or removing a case
**cannot compile** until every UI surface is addressed. Prefer that shape when
you add state to this feature.

---

## Things that are deliberately NOT done

Live, known gaps. Do not report them as new findings; do not silently "fix" one
in passing without reading the tradeoff.

- **A persistently failing resume sweep is logged and surfaced nowhere.**
  `resumeSweepUnlocked` swallows its errors so a failure cannot leave the lock
  screen up over an open session. The consequence is plaintext shares behind a
  live passcode with no user-visible signal. The correct remedy is a
  degraded-protection indicator in the UI; it is unclaimed work. Rejected three
  times as "just propagate the error" — see
  [transitions](transitions.md#it-swallows-its-own-errors-and-that-is-deliberate).

- **`storeWrappedDataKey` cannot distinguish "the write did not land" from "the
  write landed and the read-back was unavailable".** It reports failure for both.
  In `changePasscode` that means the **new passcode may be the live one while the
  UI says the change failed**. Fixing it properly is an error-taxonomy change — a
  new store error, a new `PasscodeError`, a new string in every shipping locale —
  which deserves its own review round. It is survivable because the next launch's
  mode alignment keeps the gate up and the user has just typed the new passcode
  twice. Note the tension: the read-back fails closed *on purpose*, because
  callers must never record an unverified write as durable. This gap is the price
  of that choice, and it was priced.

- **Most TSS call sites still use the optional-collapsing
  `Vault.getKeyshare(pubKey:)` rather than the throwing `keyshareValue(for:)`.**
  So a locked app and a vault with no share for that key are indistinguishable at
  those sites. `Blockchain/Tss/` is *not* one of them —
  `LocalStateAccessorImpl.getLocalState` already uses the throwing accessor and
  reports the failure through the TSS error pointer. What is left is
  `Blockchain/States/Keygen/` (`DKLSKeygen`, `SchnorrKeygen`),
  `Blockchain/States/Keysign/` (`DKLSKeysign`, `SchnorrKeysign`,
  `DilithiumKeysign`) and `KeygenViewModel`. Converting them is accessor-layer
  scope and has not been done.

- **`ProtectedVaultImporter` saves a shared `ModelContext` that may be carrying
  another flow's pending work.** SwiftData has no scoped save. The alternatives
  are refusing the import whenever anyone has unsaved work — which the lease
  placement deliberately rejected — or nothing. The *failure* path does preserve
  foreign work: `context.hasChanges` is sampled before anything is inserted, and
  a failed insert save rolls back only if the context was clean, otherwise it
  withdraws just the imported vaults one by one. The **preparation's** save is
  the one that rolls back unconditionally, and it may: it runs after the insert
  save has already flushed anything foreign, and `commit` suspends nowhere in
  between, so everything pending at that point was written by `prepare`.

- **A preparation that fails twice is logged and the import still reports
  success to the user.** The vault is stored and openable but missing at least
  one of its default chains, and only a log line says so. Throwing instead would
  refuse an import that has already reached disk, leaving the user a vault they
  can no longer re-import; telling them properly needs a new error, a new
  outcome for three import routes to render, and a string in every shipping
  locale. Unclaimed work, priced the same way as the resume-sweep gap above.

- **The keygen episode lease crosses screens.** `KeygenViewModel` takes it;
  `commitVault` is a `static` function that neither owns nor releases it. Safety
  rests on SwiftUI retaining the view model (`@StateObject` on `KeygenView`,
  which stays in the navigation stack under the review screen) plus
  `deinit`-release. This is the design's own named open question. A leaked lease
  blocks every passcode change until relaunch.

- **`ProtectedVaultImporter`'s lease brackets normalize → insert → save →
  prepare, not decode → insert → save.** Decode and commit are separated by a
  modal password prompt on the multi-file path, and a lease held across a modal
  leaks when the user walks away. Re-normalizing at commit under the lease gives
  the same guarantee. The cost is a narrow liveness case: a decode that seals,
  followed by a disable, refuses the import until the user retries.

- **No recovery path exists for stores sealed by the superseded always-encrypted
  design** (which kept a clear data key in the Keychain). Nothing shipped in that
  state, so nothing was written for an empty population. If you somehow have one:
  erase the simulator or delete the app.

- **There is no launch migration, and `KeyshareEncryptionMigration` does not
  exist.** If a document you are reading describes one, a completion marker, or a
  clear `keyshareDataKey` Keychain item, it is stale — stop and re-read the code.

---

## A hazard on the import path that predates this feature

**Pre-existing. Not introduced by the passcode work, and not fixed by it.** It is
recorded here because this is where the next person reading the import path will
be, and because its end state is the one [rule zero](#rule-zero) is about: a
share this device can never sign with again.

> An imported vault that collides with a stored one on a **single** unique
> attribute — or on nothing but its **name** — replaces it, key shares included.

`EncryptedBackupViewModel.isVaultUnique` treats an incoming vault as a duplicate
only when `pubKeyECDSA` **and** `pubKeyEdDSA` both match one already stored. But
`Vault` declares `name`, `pubKeyECDSA` and `pubKeyEdDSA` as three *independent*
`@Attribute(.unique)` properties. So a vault matching on one key, or on neither
key and only the name, passes the guard, reaches `context.insert`, and SwiftData
resolves the collision the way it always does — by **upserting** rather than by
failing, the behaviour the fixtures below are written around. The stored row is
replaced by the incoming vault's values, and `keyshares` is one of those values:
a plain stored property on `Vault`, not a related row that could survive on its
own.

No error, no prompt, nothing written to the log. The displaced share is gone
from this device, and what is left is whatever `.vult` backup the user happens to
hold. All three import routes reach it — `restoreVault`, `restoreVaultBack` and
the multi-file `importVaults` each guard with `isVaultUnique` and then commit
through `ProtectedVaultImporter`.

It is deliberately left alone rather than repaired in passing.
`ZipImportDuplicateTests` currently pins the same-`pubKeyECDSA` /
different-`pubKeyEdDSA` case as *acceptable*, so tightening the guard changes
shipped behaviour and needs its own review, its own copy and its own decision
about what a partial collision should mean. **Do not read that test as evidence
the case is safe** — it pins today's behaviour, not a judgement about it. And
note what is not covered: no test imports a vault colliding on one key alone, or
on the name alone, so nothing in the suite would notice the replacement.

---

## Tests that look paranoid and are not

Each of these is over-specified because the plain version was written first and
**passed against the live bug**:

- a concurrency test that returns early when `beginEpisode()` yields `nil` passes
  even if every acquisition is spuriously refused → count and assert the
  acquisitions;
- a lock-race test that only drives the PBKDF2 window passes against a
  generation captured too late → the hooked sweeper has to fire inside the
  **sealed-share scan**;
- serialization tests that assert only the eventual `.busy` pass against an
  implementation that takes the lease *late* → also assert no Keychain write, no
  share rewrite, no mode change;
- a "reconciliation is retried next launch" test is vacuous without asserting the
  wrapper **survives** the busy pass;
- **no assertion on stored values can distinguish a no-op write from no write at
  all** — `MockKeychainService` records every mutating call in order, and the
  first-ever-install acceptance test asserts on that list;
- SwiftData answers a duplicate `@Attribute(.unique)` with an **upsert rather
  than an error**, so a multi-vault fixture silently collapses to one row and
  three assertions pass over one vault → fixtures assert their own row count;
- an assertion on a `@Model` object the test is still holding cannot tell an
  attachment that was persisted from one that was not — which is exactly the
  failure [above](#the-write-that-did-not-take) → every fixture that asserts
  coins were attached reads them back through a **fresh** `ModelContext` on the
  same container;
- a postcondition computed from what a pass *produced* is satisfied by an empty
  list, so a preparation that built nothing at all passes as complete → the coin
  cases include a vault nothing can be built for, and one where a single chain
  fails while the others succeed;
- test doubles that upsert model semantics production does not provide (the
  `SecItemAdd` case) pass for the wrong reason → the doubles mirror
  `errSecDuplicateItem`;
- tests that exercise a unit but not the **route** cannot catch a routing
  regression, which was exactly the import bug → `BackupImportProtectionTests`
  drives the real `EncryptedBackupViewModel`;
- any test that installs `Storage.shared.modelContext` must use
  `TestStore.installInMemoryContainer()` / `TestStore.restore(token)`, or it
  crashes every later suite in the process.

New regression tests here are expected to **fail against the parent commit**.
Check that explicitly; a test that passes both ways is documenting nothing.

---

## Before you change this code

1. Read [the overview](overview.md), then the page for the area you are in.
2. Ask which of the three states the change is reachable in, and what it does in
   `.disabled` — that is most users, forever.
3. Ask what a crash immediately after your new statement leaves on disk, and
   which existing repair path finds it.
4. If you touched ordering, re-read [the table above](#ordering-constraints--do-not-reorder-these).
5. Run the full `VultisigApp/VultisigAppTests/Security/` and
   `VultisigApp/VultisigAppTests/Storage/` suites, not a subset — plus
   `VultisigApp/VultisigAppTests/Services/VaultDefaultCoinServiceTests.swift` if
   you touched what the import hands to `prepare:`.
6. If you added a `PasscodeError` case, follow the exhaustive switch the
   compiler points you at rather than defaulting it.
