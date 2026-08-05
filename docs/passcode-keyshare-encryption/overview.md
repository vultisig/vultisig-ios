# Passcode and key-share encryption — overview

**Read this before changing anything under `Core/Security/Keyshare/` or
`Core/Security/Passcode/`.** That code holds key material. A mistake there is
lost funds, not a bad screen: a key share that cannot be opened is a vault that
can never sign again, and there is no server-side copy to restore from.

- [Key hierarchy](key-hierarchy.md) — what encrypts what, and why changing a passcode moves 32 bytes
- [Concurrency and the write coordinator](concurrency-and-leases.md) — the three leases and the races each closes
- [Transitions](transitions.md) — set / disable / change / resume, step by step, with what survives a crash at each step
- [Invariants and traps](invariants.md) — the list of things that look like safe cleanups and are not

---

## The invariant

> **A key share is sealed if and only if a passcode is currently set.**

"Currently", not "ever" — which is what forces `disablePasscode` to open every
share back to plaintext rather than merely removing the gate. Everything else in
this feature follows from keeping that sentence true across crashes, concurrent
writes, reinstalls and app downgrades.

## The acceptance test

> **A user who never sets a passcode must be byte-for-byte indistinguishable
> from an app build without this feature.**

Concretely, with no passcode set:

| Surface | Must be |
|---|---|
| `KeyShare.keyshare` on disk | plaintext, byte-identical |
| Keychain | no wrapped data key, no attempt-limiter record, no biometric copy, no marker of any kind |
| Launch | no key-material rewrite, **and no other new Keychain mutation** — not even a no-op delete |
| `.vult` export / import | unchanged bytes, restores on any build, any platform |
| TSS keygen / keysign / reshare | unchanged values reach `LocalStateAccessorImpl` |
| Downgrade to an older build | works, forever, with no action required |

That last row is why the feature is opt-in rather than encrypting everyone. An
older build has no `vlt2:` awareness: it reads a sealed share and hands the
literal string `"vlt2:…"` into the TSS layer, so signing fails for someone who
never chose anything, and a `.vult` exported from that build contains ciphertext
and is dead on every other device. This repo is open source and contributors
hop between branches constantly — reviewing a PR branch and then running `main`
is a downgrade in the sense that breaks. Opt-in confines that hazard to people
who deliberately turned the feature on, and `disablePasscode` is a real inverse
they can press to get out of it.

The cost is recorded honestly: optional security settings see single-digit
adoption, so most installs — macOS especially — hold plaintext key material.
That was decided, not overlooked.

## The three protection states

`KeyshareProtectionState` (in `KeyshareProtector.swift`) has exactly three cases,
and `KeyshareKeySession.currentState()` is the only thing that produces them:

```
                        cached key in memory?
                                 │
                    ┌────────yes─┴─no────────┐
                    ▼                        ▼
             .unlocked(key)        read the wrapped data key
        seal and open both work     from the Keychain
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    ▼                        ▼                        ▼
                .present                 .absent                .unavailable
                    │                        │                        │
                    ▼                        ▼                        ▼
                 .locked                 .disabled                 .locked
        a passcode exists,          no passcode; shares      fail closed — the
        the key is not in hand      are plaintext            Keychain may hold
        → open throws               → seal is a passthrough   a wrapper we
        → seal throws               → open passes plaintext   cannot see
                                       through
```

`.disabled` is the **majority and permanent** state, not a transient one before
some migration. Most installs are in it and stay in it forever. That is why
`KeyshareProtector.open` checks `isSealed` *before* consulting the state and
returns a plaintext value unchanged whatever the state is — a store part-way
through a sweep still signs correctly.

`.unavailable → .locked` is deliberate and was challenged on review. Reading an
unreadable Keychain as `.disabled` is a licence to write plaintext behind a
passcode that is still set — silently, and only for the users who opted in.
Reading it as `.locked` fails a keygen or an import visibly and the user
retries. The exposure is also narrower than it looks: with no passcode there is
no wrapped item at all, and a Keychain query matching no item answers
`errSecItemNotFound` whatever the device's lock state, so reaching that line
without a passcode takes a Keychain-wide fault that the fast-vault password read
would be failing on too.

## What a user who never sets a passcode gets

Nothing. Not "an encrypted store with the key lying around" — nothing:

- no data key exists in any form, wrapped or clear. There is no unwrapped
  resting state of the key anywhere in the design;
- `KeyShare.sealed(...)` calls `KeyshareProtector.seal`, which returns the
  plaintext unchanged in `.disabled`. Keygen, reshare, key import and backup
  import all route through it, so every write is a passthrough;
- `Vault.mapToProtobuff` opens each share before writing the `.vult`, and `open`
  passes plaintext through, so export is byte-identical;
- `KeyshareInstallReconciler` reads three items (wrapper, attempt-limiter state,
  biometric copy) and, on three *confirmed* absences, issues **no Keychain
  mutation at all** — not even a no-op delete, which still reaches
  `SecItemDelete` and still counts. Confirmed, not assumed: an `.unavailable`
  read defers the whole pass to the next launch rather than issuing deletes;
- the whole feature is additionally behind `PasscodeFeatureFlag`, off by default
  (`SettingsViewModel.passcodeFeatureEnabled`, toggled from Settings →
  Advanced), so the Settings entry does not even appear.

## Who owns what

```
 Storage                     Cryptography                 Policy / lifecycle
 ───────                     ────────────                 ──────────────────
 KeychainReadResult          VaultCryptoEnvelope          PasscodeService (actor)
   absent/present/             VLT\x02 blob format          set / change / disable
   unavailable                 AES-GCM + PBKDF2 600k        unlockApp / unlock
        │                            │                      resumeSweepUnlocked
        ▼                            ▼                             │
 DefaultKeyshareKeyStore     AesGcmKeyshareCipher                   │
   the wrapped data key        the "vlt2:" prefix                   │
   store/load/delete           seal / open one share                │
   wrap / unwrap                      │                             │
        │                             ▼                             │
        └──────────────────►  KeyshareProtector  ◄──────────────────┘
                               the ONE place a stored value
                               becomes a usable one
                                      ▲
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
            KeyshareSweeper   ProtectedVaultImporter  KeyShare.sealed
            whole-store        every backup format     every write path
            seal/unseal        normalizes on import
                    │                 │                 │
                    └────────► KeyshareWriteCoordinator ◄┘
                               transition / write / episode leases

 KeyshareKeySession     the opened key, in memory, + the lock generation
 KeyshareInstallReconciler  launch: Keychain vs. container vs. lock mode
 BiometricUnlockStore   optional shortcut; a second copy of the key, bound
 PasscodeAttemptLimiter the in-app guessing throttle
 AppLockService         which gate is in use (off / deviceAuth / passcode)
```

Read paths: `Vault.keyshareValue(for:)` throws so a locked app is
distinguishable from a vault with no share; `Vault.getKeyshare(pubKey:)` is the
`try?` collapse over it and most TSS call sites still use that one — see
[invariants](invariants.md#things-that-are-deliberately-not-done).

Write paths: `KeyShare.sealed(pubkey:keyshare:keyId:)` for anything that mints a
share, `ProtectedVaultImporter` for anything that comes in from a file.

## Where the tests are

`VultisigApp/VultisigAppTests/Security/` — one file per type, plus
`BackupImportProtectionTests` (drives the real `EncryptedBackupViewModel`
through every import route) and `PasscodeLaunchGateTests`.
`VultisigApp/VultisigAppTests/Storage/KeychainTriStateReadTests.swift` covers the
tri-state read the whole design rests on.

Several of those tests look over-specified. They are: the plain version of each
was written first and **passed against the live bug**. See
[invariants](invariants.md#tests-that-look-paranoid-and-are-not).
