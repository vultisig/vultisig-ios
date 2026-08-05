# Concurrency and the write coordinator

`KeyshareWriteCoordinator` exists because the invariant — *a share is sealed iff
a passcode is set* — is a statement about the whole store, and a passcode
transition rewrites the whole store while other code is writing shares into it.

## The two races it closes

### 1. Two transitions interleaving

`PasscodeService` is an `actor`, and **actors are reentrant at every `await`**.
`setPasscode` suspends inside `keyStore.wrap` for roughly half a second of
PBKDF2. Two calls can both clear `guard !isSet`, both mint a key, and interleave
their store / adopt / sweep steps — leaving shares sealed under a key the
surviving wrapper does not wrap. `changePasscode` and `disablePasscode`
interleave the same way.

Being an actor is necessary (it serializes the read-modify-write over the
attempt limiter's Keychain state) but nowhere near sufficient.

### 2. A share computed under one protection state, persisted under another

`LocalStateAccessorImpl.saveLocalState` is a **synchronous callback the TSS layer
makes from an arbitrary thread**. It seals a share the moment TSS hands it over.
If the seal and the store are not one indivisible span:

| Interleaving | Result |
|---|---|
| seal at `.disabled` → sweep runs → append | plaintext share in a passcode-protected store. Invariant broken, silently |
| seal under the key during a disable → wrapper deleted → append | **sealed share, key gone, permanently unreadable** |

The second is genuine fund loss. An earlier version of the design claimed "there
is no window that silently writes an unsealed share" on the grounds that `seal`
throws in `.locked`. That is false: the `.locked` branch only covers a call that
*enters* `seal` during the window. It does nothing for a callback that sealed
earlier and persists later.

There is a third shape of the same race with a much longer lifetime: TSS produces
a share, and `KeygenViewModel` persists it at `commitVault` — which, on the
deferred path, is the user tapping "Looks Good" on the review screen, possibly
minutes later. A passcode set landing in that interval sweeps a store that does
not yet contain the share, and the share is then inserted in plaintext behind a
live passcode.

## Why `NSLock` and not `@MainActor`, and not an actor

An earlier revision proposed a `@MainActor` flag plus an in-flight-write counter.
**Both halves could not work**, and the review that killed them is worth not
repeating:

- `saveLocalState` is *synchronous*. Reaching a main-actor lease from it needs
  either a `Task` hop — which puts the seal outside the span that is the entire
  point — or `DispatchQueue.main.sync`, which **deadlocks** whenever the callback
  already runs on main.
- a per-write counter does not cover the TSS-produces → `commitVault`-persists
  interval at all.

So the coordinator is an `NSLock`-backed class with **no suspension points**,
callable synchronously from any thread — the same shape `KeyshareKeySession`
already uses successfully on this exact call path. It is deliberately not
`@MainActor` and deliberately not an `actor`. Do not "modernize" it.

## The three lease levels

Three hazards, three lifetimes, three levels:

| Lease | Taken by | Span | Prevents |
|---|---|---|---|
| `TransitionLease` | `setPasscode`, `changePasscode`, `disablePasscode`, `KeyshareInstallReconciler.reconcile` | one whole transition, claimed **before the first `await`** | two transitions interleaving across key derivation |
| `WriteLease` (`withWriteLease` / `beginWrite`) | see the per-caller table below | one span that a transition must not split | a transition landing in the middle of a multi-step write |
| `EpisodeLease` | `KeygenViewModel.startKeygen`, `ProtectedVaultImporter.commit` | a whole keygen / reshare / import, start through commit **or** discard | a share produced before a transition and committed after it |

**A write lease does not mean "one seal and its persistence".** That is only the
`saveLocalState` case. What the lease actually guarantees is narrower and
uniform: *no passcode transition begins or completes inside this span.* What the
span contains differs per caller, and conflating them hides which invariant each
one is buying:

| Caller | What the span actually covers | What a transition splitting it would do |
|---|---|---|
| `LocalStateAccessorImpl.saveLocalState` | seal a share **and** append it to the in-memory array | seal under one protection state, persist under another |
| `KeygenViewModel.commitVault` | insert **and** `save()` shares sealed earlier in the episode | commit shares the sweep never saw |
| `PasscodeService.unlockApp` / `unlockWithBiometrics` | verify or biometric-match, adopt the key, **and** run the resume sweep | a disable deleting the wrapper mid-unlock, or a sweep racing a transition |
| `enableBiometricUnlock` / `disableBiometricUnlock` | write or delete the biometric copy only — no share is touched | a copy created just after a disable removed it, i.e. the orphan the binding exists to catch |

Exclusion matrix — this is the whole semantics:

```
                    can start while ...
                    transition   write     episode
                    held?        in flight? open?
  transition          NO           NO        NO
  write               NO           yes       yes
  episode             NO           yes       yes
```

A transition is exclusive against everything. Writes and episodes do not exclude
each other, so ordinary vault creation is never serialized against itself.

Contention is reported as `.busy`, **not queued**. A passcode toggle that waits
silently for a keygen to finish looks like a hang; "finish creating your vault
first" is the honest version of the guarantee, and the alternative is a lock-free
protocol nobody can review.

## Leases release on `deinit`

`KeyshareLease` releases on `deinit` as well as on `end(_:)`, and releasing twice
is a no-op. That is not tidiness — an episode brackets a flow with a great many
error and cancellation paths, and **a leaked lease blocks every passcode change
until the app is relaunched**. Holding the token in a `defer`, or in a property
that goes away with the flow, is therefore enough.

`NSLock` is not recursive and `release()` reaches back into the coordinator, so
every coordinator lock is dropped before bodies and release callbacks run, and
the lease's own lock is dropped before it calls back. There are regression tests
named for exactly this (a lease deallocated inside a write body; an episode
deallocated while a write runs). If you refactor the locking, run them.

## The app unlock takes a WRITE lease, not a transition lease

This is the single most important thing on this page to not undo.

`beginTransition()` is refused while an **episode** is open, and
`KeygenViewModel` deliberately holds one through the deferred "Looks Good"
commit. If the app unlock took a transition lease, an app that auto-locked while
sitting on the review screen **could never be opened again**: the keygen flow
cannot be finished without unlocking, and unlocking could not happen while the
flow is open. Permanent, user-visible, and it costs the user the vault they just
created.

`beginWrite()` is the same accounting `withWriteLease` uses, exposed as a token
an `async` caller can hold across an `await`. It excludes set / change / disable
— which is all an unlock actually needs — and is refused by no episode. Both
`unlockApp` and `unlockWithBiometrics` use it, for exactly this reason.

Consequence for copy: on the lock screen, `.busy` means *another unlock or a
transition*, never "a vault is being created". The string is worded to be true on
every path rather than actionable on one.

## What the coordinator does NOT protect

`PasscodeService.lock()` is `nonisolated` and stays **outside** the coordinator
on purpose: a background scene-phase lock must never block on a transition, and
it must never be undone by one. It is synchronized only through
`KeyshareKeySession`'s own lock.

Winning is therefore arranged by generation counting, not by mutual exclusion.
Every operation that will adopt a key captures `session.currentGeneration` as
close to its **first instruction** as possible, and adopts via
`adopt(_:ifGeneration:)`. `lock()` bumps the generation, so a lock that landed
mid-derivation makes the adopt fail and the operation throws `.cancelledByLock`.

That capture placement is a real bug that was caught: reading the generation
after the first `await` (the sealed-share scan) let a `lock()` landing during the
scan be silently undone, leaving the key live in memory behind a lock screen.
**If you add a statement above the generation capture in `setPasscode` or
`unlock`, you are widening that window.** The residual window — a `lock()`
between the call and that first instruction — is one instruction wide and is
accepted, not closed; closing it would require `lock()` to synchronize with the
actor, which the design rules out.

## What the coordinator also does not cover: overlapping unlocks

Because write leases do not exclude each other, two app unlocks can overlap. Two
actor-isolated flags close that, each read and set **with no `await` between
them** (which is what makes them atomic inside the actor):

- `isAppUnlockInFlight`, around `unlockApp` and `unlockWithBiometrics`. Without
  it, a slower unlock's post-sweep generation check can clear a faster one's
  perfectly good session.
- `isVerifyingPasscode`, around `unlock(with:)`. Without it, overlapping attempts
  all clear the attempt limiter's lockout check *before any of them records a
  failure* — a burst of guesses collapsing into one counted failure, i.e. the
  brute-force throttle switching itself off exactly when it is under attack.
  This one covers every caller, including the change flow's verification.

## Sequence: a TSS write versus a disable

```
  TSS thread                  coordinator            main actor (disable)
  ──────────                  ───────────            ────────────────────
  withWriteLease {                                   beginTransition()
      seal(share)  ────────►  writesInFlight = 1 ──►  refused: .busy
      append                                          (user retries)
  }                ────────►  writesInFlight = 0
                                                     beginTransition() ✓
                              transition held  ───►  unseal all, delete wrapper
  withWriteLease {  ───────►  refused: .busy
      ...
```

Either order is safe. What is *not* safe, and is what the lease makes
unreachable, is the seal landing on one side of the transition and the append on
the other.
