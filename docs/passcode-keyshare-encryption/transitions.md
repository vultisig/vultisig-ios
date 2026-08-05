# The transitions

Four operations move the store across the invariant or repair it:
`setPasscode`, `disablePasscode`, `changePasscode` and the resume sweep that
every app unlock runs. The step order in each is not stylistic — every position
below closes a specific way of losing key material, and the "what survives a
crash here" column is the argument.

Two of them are cheap and two are not:

- `changePasscode` rewraps the 32-byte data key into **one 80-byte wrapper** and
  touches no key share at all.
- `setPasscode` and `disablePasscode` **cross the invariant**, so each rewrites
  every stored share. Both are transactional, both take the exclusive transition
  lease, and both are resumable.

---

## `setPasscode(_:)`

```
 0  lease = coordinator.beginTransition()            → .busy if a write or episode is open
 1  generation = session.currentGeneration           ← FIRST instruction after the lease
 2  validate(passcode)
 3  guard !isSet                                     → .alreadySet   (fails closed on .unavailable)
 4  guard !sweeper.hasSealedShare()                  → .sealedSharesWithoutKey
 5  if biometrics.isEnabled { biometrics.disable() } → throws; nothing has changed yet
 6  dataKey = keyStore.generateDataKey()             ← in memory only
 7  wrapped = await keyStore.wrap(dataKey, passcode) ← ~0.5s of PBKDF2; SUSPENSION POINT
 8  keyStore.storeWrappedDataKey(wrapped)            ← writes AND reads back
 9  lockService.mode = .passcode                     ← the moment the wrapper is durable
10  session.adopt(dataKey, ifGeneration: generation) → .cancelledByLock if a lock landed
11  sweeper.sealAll()                                ← verified per share
12  limiter.recordSuccess()
```

### What survives a crash at each step

| Crash after | Store state | Recovery |
|---|---|---|
| 1–4 | nothing written anywhere | none needed |
| **5–7** | a leftover biometric copy has been deleted; nothing else written | none needed — that copy could never have opened anything |
| **8** | wrapper durable, `mode` still whatever it was (`.deviceAuth` **or** `.off` — this step has not touched it), all shares plaintext | launch reconciliation sees a present wrapper and restores `.passcode`; the next unlock's resume seals |
| **9** | wrapper durable, gate up, all shares plaintext | unlock → resume seals everything |
| **10**, or anywhere inside 11 **before its save lands**, or a sweep that simply *fails* | wrapper durable, gate up, shares **still plaintext** — the *pending-passcode* state | unlock → resume seals them |
| **11**, after its save returned | wrapper durable, gate up, **all shares sealed** — the finished state bar the throttle reset | none needed |
| 12 | done | none |

The sweep itself is not a partial-write hazard, which is why those two rows have
a hard edge between them rather than a gradient: `KeyshareSweeper` computes and
verifies everything first and then commits **one** `context.save()`. Before that
save the store is untouched; after it, every share is sealed. Pending-passcode is
therefore exactly "durable wrapper, gate up, sweep not applied", and resume is
what applies it.

A genuinely **mixed** store — some shares sealed, some plaintext — is still
reachable, just not from this path: a keygen commits a share sealed under the
adopted key while resume has not yet run over the older plaintext ones, or an app
downgrade writes a plaintext share into a sealed store. That store signs
correctly regardless, because `open` passes a plaintext value through whatever
the state, and the next unlock's resume closes it.

There is no state in that table where a sealed share exists without a durable
wrapper. That is the property the ordering buys.

### Why step 8 comes before step 11

The tempting order — mint, seal everything, then store the wrapper — orphans
**every** sealed share if the process dies in between, because the key only ever
lived in memory. Unrecoverable.

### Why step 9 moved up

With `mode = .passcode` at the *end* (an earlier revision), a failed sweep left a
durable wrapper while the mode stayed `.deviceAuth`. The consequence chain:

```
  sweep fails
    → mode stays .deviceAuth
    → launch shows no passcode gate
    → resume only runs on an app-passcode unlock, which never happens
    → retry fails with .alreadySet (the wrapper IS there)
    → the passcode is durable and unreachable. Permanently.
```

Setting `.passcode` the moment the wrapper verifies means the next launch shows
the gate, the unlock runs resume, and the sweep finishes.

The cost of moving it up is that a throw from `setPasscode` no longer means
"nothing durable happened", and the UI had to learn that — see
[the UI note](#a-throw-does-not-mean-nothing-happened) below.

### Why a failed sweep must NOT delete the wrapper

An earlier revision said the failure path should clean up by deleting the
wrapper. **That is unsafe**, and the reason is not that today's sweeper is
sloppy — it is that the failure does not tell you whether anything was sealed.
`KeyshareSweeper` as written is two-phase and rolls back, so a thrown `sealAll`
happens to leave nothing sealed; that is a property of one implementation, not of
the contract this ordering has to survive. And the consoling argument that made
deletion look safe — "a later `setPasscode` re-sweeps idempotently" — is false
either way: a newly minted key **cannot open ciphertext produced by the discarded
one**.

So the app stays in the pending-passcode state and resume completes it. Deleting
the wrapper is only safe in the window where sealing has *provably* not started,
i.e. between steps 8 and 9.

That also makes step 4's guard coherent rather than over-broad: a **completed**
disable leaves nothing sealed, so re-enabling works; an **interrupted** set
leaves a wrapper, so `guard !isSet` refuses first and resume — not a fresh mint —
is the recovery.

### Step 4, "never mint over evidence"

A sealed share plus no readable wrapper means a key already exists somewhere,
and the key generated at step 6 opens none of what that one sealed. So the set is
refused with `.sealedSharesWithoutKey` rather than completed.

`hasSealedShare()` **refuses a dirty `ModelContext`** (mapped to
`PasscodeError.busy`), and that is not symmetry for its own sake. A SwiftData
fetch answers from the context's *pending* state, so an unsaved edit or an
uncommitted deletion can present a vault as plaintext — or hide it entirely —
while the durable row is still sealed. Without the refusal the scan returns
`false`, a wrapper is stored, and *then* the sweep at step 11 fails `.busy`
because the same dirty context is refused one layer down: the set fails **after**
the wrapper is durable. With it, the set fails **before a key is minted**, which
is strictly the better failure.

### Step 5, and why it is before step 6

The biometric copy holds the *same* data key. A copy with no passcode behind it
is a leftover — a previous install's, or one a reconciliation could not clear —
bound to a wrapper that no longer exists, so it could never open the app. What it
*can* do is report biometric unlock as already enabled for a passcode the user is
only now creating. Failing here is deliberate, and it is clean: nothing has
changed yet.

---

## `disablePasscode(current:)`

The exact inverse of `setPasscode` where key material is concerned: no data key
in any form, and every share byte-identical to what a device that never had a
passcode would hold.

One thing does not come back. `AppLockMode` has three cases, and this writes
`.deviceAuth` unconditionally — so someone who was on `.off` before they set a
passcode lands on `.deviceAuth`, not back on `.off`. That is a `UserDefaults`
preference they can change again, not key material.

```
 0  lease = coordinator.beginTransition()
 1  wrappedBeforeVerification = loadWrappedDataKey().valueTreatingUnavailableAsAbsent
 2  await unlock(with: current)                      ← key in memory
 3  biometrics.disable()                             ← BEFORE a single share moves
 4  wrapped = wrappedBeforeVerification ?? loadWrappedDataKey().value…
 5  sweeper.unsealAll()                              ← the GCM open IS the verification
 6  lockService.mode = .deviceAuth                   ← BEFORE the wrapper goes
 7  keyStore.deleteWrappedDataKey()                  ← on failure: restore, then rethrow
 8  session.clear()
```

### What survives a crash at each step

| Crash after | Store state | Recovery |
|---|---|---|
| 1–2 | unchanged; passcode fully working | none needed |
| **3–4** | passcode fully working, but the biometric shortcut is gone | none needed; the user re-enables it |
| **5** (crash inside the unseal, or an unseal that fails) | wrapper present, mode `.passcode`, shares **still sealed** — the unseal is one `save()`, so it is all or nothing | nothing to repair; the passcode still works and the user presses disable again |
| **5**, after its save landed | wrapper present, mode `.passcode`, all shares plaintext | resume on the next unlock re-seals them; user presses disable again |
| **6** | wrapper present, mode `.deviceAuth`, all shares plaintext | reconciliation restores `.passcode`; resume re-seals; user presses disable again |
| **7** | no wrapper, mode `.deviceAuth`, all shares plaintext | this is the finished state |
| 8 | done | the key is only in memory; the process died, so it is gone |

### Why the mode changes before the wrapper is deleted

With the reverse order, a crash after the deletion but before the mode change
leaves plaintext shares behind `mode == .passcode` and **no wrapper to unlock
against**. `unlock` has nothing to verify a passcode against, so that gate can
never be opened — on a store that needs no protection at all.

The mode-first order creates its own, smaller window (row 6 above): plaintext
shares, wrapper present, persisted `.deviceAuth`. `KeyshareInstallReconciler`'s
*present ⇒ `.passcode`* direction repairs exactly that, and its worst case is a
disable the user presses twice. The reverse order's failure has no repair at all.
That asymmetry is the whole argument.

### Why the biometric copy goes first

It holds the same data key, so a survivor would quietly work again the next time
a passcode is set. And failing to remove it *after* the shares had already been
opened would report an error over a passcode that is half gone. At step 3 nothing
has changed, so aborting is clean.

It is called directly rather than through `disableBiometricUnlock()`, because
that method takes a write lease and this call already holds the transition lease
the write would be excluded by.

### If the delete fails

One protocol, not a choice: **prove the wrapper is durable, restore
`.passcode`, reseal transactionally, throw.** The app is back to a working
passcode and the user retries.

Proving the wrapper first is not belt and braces. `deleteWrappedDataKey` reports
failure on an **unreadable read-back** too, so "it threw" does not mean "the item
is still there". Resealing on that assumption produces ciphertext whose only key
is in memory, until the next `lock()` destroys it. So
`restorePasscodeAfterFailedRemoval` re-stores the wrapper — and therefore
read-back-verifies it — *before a single share is resealed*.

If the wrapper cannot be made durable, nothing is resealed **and the session is
cleared**. Plaintext shares with no key anywhere is precisely the no-passcode
resting state, and it is the only outcome here that loses nothing. Clearing the
session matters: leaving the key cached would let a keygen or reshare seal a new
share against a key nothing on disk wraps, and the first lock after that makes
that share unreadable forever.

Step 1 and step 4 read the wrapper on **both sides** of the verification for the
same reason. `unlock` cannot succeed without reading that item, so a read that
comes back unreadable on one side of it is transient rather than meaningful — and
without those bytes the rollback has nothing to restore, which is the difference
between "the passcode is back" and "plaintext shares behind a mode that says
there is no passcode".

---

## `changePasscode(current:new:)`

```
 0  lease = coordinator.beginTransition()
 1  validate(new)
 2  dataKey = await unlock(with: current)            ← verification; throttled
 3  rewrapped = await keyStore.wrap(dataKey, new)
 4  keyStore.storeWrappedDataKey(rewrapped)          ← one 80-byte wrapper; read-back verified
 5  rebindTheBiometricCopy(to: rewrapped, dataKey:)
```

**No key share is read or written.** The ciphertext on disk is byte-identical
before and after, and there is a test that asserts it. That is what makes this
safe to do casually.

It still takes the transition lease, because it rewrites the one item every
sealed share depends on. Interleaving with a set or a disable is how a wrapper
ends up holding a key that matches nothing on disk.

Step 5 is required rather than cosmetic: the biometric copy is bound to the exact
wrapped blob it was made for, and step 4 replaces that blob. Without the rebind
the shortcut stops working the moment anyone changes their passcode. Rebinding
costs no prompt — writing the Keychain item never asks for a face, only reading
does — and the data key has just been verified. If it cannot be rebound the copy
is **removed** instead; a stale binding is refused at the next unlock anyway, and
leaving one advertises a shortcut the app will not honour. A failure to remove it
is logged rather than thrown: the change itself succeeded and the leftover cannot
open anything.

---

## Resume on unlock

One rule, no persisted marker, nothing that can fall behind:

> **With the data key in hand and a wrapper present, seal any share that is still
> plaintext.**

That finishes an interrupted `setPasscode`, re-establishes the invariant after an
interrupted `disablePasscode`, and closes "plaintext introduced by an app
downgrade stays plaintext forever" as a side effect.

It deliberately does **not** try to tell an interrupted disable from an
interrupted set. With the wrapper still present there is no way to, and guessing
"disable" would silently remove protection. Restoring the invariant is
unambiguous and fails safe — worst case is a disable the user presses twice.
(An earlier design page says resume should detect the inverse and complete the
disable. That was rejected; this overrides it.)

### Wiring rules

- invoked from **exactly two places**: `unlockApp(with:)` and
  `unlockWithBiometrics(reason:)`, before either tells the caller the app is
  open;
- **never** from `unlock(with:)`, which is passcode *verification* and is what
  `changePasscode` and `disablePasscode` also call. Firing it there would run a
  store-wide sweep in the middle of a change;
- `resumeSweepUnlocked()` is **non-acquiring, and there is deliberately no
  acquiring variant.** Both app-unlock paths already hold a lease that excludes
  transitions. An acquiring `resumeSweep()` would ask the coordinator for a lease
  from inside a held one — which is exactly what the coordinator refuses — so it
  would throw `.busy` on the single path that must work every time. The missing
  API reads like a completeness gap; it is not;
- the latch is keyed on the **session generation**, not a boolean. `lock()` is
  `nonisolated` and cannot touch actor state, so bumping the generation *is* the
  reset. Plaintext introduced after a successful sweep is picked up on the next
  lock cycle rather than never;
- the latch is set **only on success**, so a failed resume retries on the next
  unlock.

### It swallows its own errors, and that is deliberate

`resumeSweepUnlocked` catches everything and logs. `unlockApp` returns success
regardless. This was raised as a finding three separate times and rejected three
times, so here is the reasoning in full:

the key is **adopted before** the resume runs, so the session *is* open by then.
Propagating the error would leave the lock screen up over an unlocked session,
and a persistent cause — one share that will not open, an unsaved edit somewhere
in the store — would lock a user out of an app whose passcode they know. That
trades a partial-protection exposure for a total loss of access.

What *is* true and is not hidden: **a persistently failing resume leaves
plaintext shares behind a live passcode, logged at error level and surfaced
nowhere.** The right fix is a degraded-protection indicator in the UI. It is
unclaimed work, not a solved problem. The doc comment on `unlockApp` says
"attempts", not "guarantees", for this reason — do not tighten that wording
without building the indicator.

### The generation check on both sides

Both unlock paths capture the generation before the first suspension point and
**re-check it after the resume**, clearing the session and throwing
`.cancelledByLock` on a mismatch. `unlock` only guards the *adoption* against a
lock; without the second check, a lock landing during the sweep would still be
followed by a successful return, and the caller would dismiss the lock screen
over a session that is locked again.

There is one more gap after that, in the UI: `lock()` can land between
`unlockApp` returning and the overlay flag moving. `PasscodeService.isSessionUnlocked`
is `nonisolated` precisely so no `await` can open a gap between asking and
acting. Three callers, three shapes, all of them making a lock win:

- `AppViewModel.markPasscodeUnlocked()` checks it immediately before the flag
  moves, with nothing in between;
- `PasscodeViewModel.unlockWithBiometrics(reason:)` derives the flag *from* the
  check — `didFinish = service.isSessionUnlocked`;
- `PasscodeViewModel.unlock()` cannot do either, because the shared `perform`
  helper sets `didFinish` on success. So it re-checks the instant `unlockApp`
  returns and puts `didFinish` back to `false` if a lock landed, clearing the
  entry so the passcode can be retyped.

---

## Launch

```
  ContentView.onLoad
        │
        ▼
  AppViewModel.restorePasscodeLockOnLaunch()
        │
        ├─► KeyshareInstallReconciler().reconcile()      ← SYNCHRONOUSLY, first
        │        │
        │        ├─ take the transition lease, or skip entirely and leave
        │        │  the container unmarked so the next launch retries
        │        ├─ clear inherited key material if the container is new
        │        └─ align the lock mode with the wrapped key, both directions
        │
        └─► if isPasscodeGateRequired: lock() and raise the gate
```

**The ordering is the point.** `KeyshareInstallReconciler().reconcile()` also
runs from `VultisigApp`'s `onAppear`, but nothing orders that against
`ContentView.onLoad` — so the gate could be chosen from a mode reconciliation was
about to change, after which the app sits open for the whole session with a
wrapped key and no lock screen. Running it here makes the ordering hold by
construction rather than by luck. A second pass is a no-op: the destructive half
is marked once per container, and the alignment only writes when the two
disagree.

The reconciler takes the **transition lease** around everything it decides or
writes; only the store-occupancy read that feeds it sits just outside. Without it,
a launch landing between `setPasscode` verifying its wrapper and adopting the key
would delete that wrapper *and mark the container done* — leaving the data key
live in memory with nothing on disk that wraps it. If the lease cannot be taken
it skips entirely and leaves the container unmarked.

Its three-valued reads exist for the same reason everything else here is
three-valued. Store occupancy is `empty` / `occupied` / **`unknown`**, and
`unknown` **defers the inherited-material clear and leaves the marker unset**
 — the lock-mode alignment below still runs, because a gate that disagrees with
the wrapper has to be repaired whether or not the store could be read. Counting
an unreadable store as occupied
would set the permanent marker and retire the clear for good, so a genuinely new
container whose store stuttered at launch would keep the previous install's
wrapped data key forever — a passcode gate nobody can open and reinstalling
cannot remove, which is the exact failure this type exists to prevent. Inherited
key material is `nothing` / `something` / `unknown` on the same principle, and
`unknown` defers that clear rather than issuing deletes, because deletes on a
first-ever install are a launch-time Keychain mutation the acceptance test
forbids.

`lastMigratedVersion` is deliberately **not** cleared. It is Keychain-held so it
survives reinstalls, and clearing it would re-run every ordinary migration on a
container with no passcode artifact of any kind.

---

## The gate is derived, never cached

`AppViewModel.isPasscodeLocked` is what the user is looking at, and it is a copy
of `PasscodeService.isPasscodeGateRequired` taken at the moment the overlay went
up. One transition invalidates that copy in the worst way available. A
`disablePasscode` **past its abort cut-off** completes even across a background
`lock()` — stopping there would strand every share in the clear behind a passcode
still being demanded — and what it completes into is `.deviceAuth`, no wrapper,
and a screen whose only exit calls `unlockApp`, which can now answer nothing but
`notSet`. Nothing typed there is ever right; force quitting is the only way out.

So the predicate is asked again rather than remembered:

```swift
nonisolated var isPasscodeGateRequired: Bool {
    guard lockService.mode == .passcode else { return false }
    if case .absent = keyStore.loadWrappedDataKey() { return false }
    return true
}
```

Both halves matter. It is the mode **and** a wrapper that is not *confirmed*
gone, so an unreadable Keychain leaves a real gate standing while a provably
removed passcode takes one down. `disablePasscode` guarantees it is `false` by
the time it returns, and `unlockApp` repairs a mode it finds standing over a
confirmed absence on the spot, for the person already at the gate.

Every site that raises or lowers the overlay derives it:

| Site | Asks |
|---|---|
| `restorePasscodeLockOnLaunch()` — cold start | after reconciliation, never before |
| `enableAuth()` — foreground | which gate this install has: raise, or lower a stale one and fall through to device auth |
| `EnterPasscodeScreen`'s failed attempt | reports; `lowerPasscodeGateIfNoLongerRequired()` decides |

Reading `AppLockService.mode` at either of the first two is the bug this
replaced, and it is a strict narrowing rather than a change of policy — the
predicate's own first clause is that mode check.

**Each site derives it exactly once and every branch acts on that one answer.**
`raisePasscodeGate()` deliberately does *not* re-derive: a transition runs on
`PasscodeService`'s executor rather than the main one, so a second read can
disagree with the first, and `enableAuth`'s passcode branch returns past the
device-auth fallback. Split across two reads, a foreground could raise no gate,
skip the fallback, and put the wallet on screen behind neither.

Not forgetting the data key when no gate is required is deliberate too: with the
wrapper confirmed gone, the session key is the last copy of something nothing can
hand back.

---

## A throw does not mean nothing happened

`setPasscode` stores the wrapper and switches the mode *before* the sweep, so a
sweep failure leaves a **working passcode** while the screen shows an error and
offers a retry whose only possible answer is `.alreadySet` — a dead end.

`PasscodeViewModel` closes the set flow on exactly one error: `.cancelledByLock`.
That error is thrown from a **single guard**, after the wrapper has verified and
after the mode has moved, so it is the one failure that *proves* the typed
passcode is durable.

The first attempt at this asked `isSet` instead, and it was wrong twice over:
`isSet` answers `true` for an **unreadable** wrapper as well as a present one,
and it cannot tell a wrapper this call wrote from one that was already there. A
failed read-back, or a transition refused while somebody else's set completed,
would have dismissed the screen over a passcode the user never set.

A sweep that fails after the wrapper is durable also leaves a working passcode,
but nothing distinguishes it from a sweep-shaped failure *before* the wrapper, so
it reports the error and `.alreadySet` explains the retry.
