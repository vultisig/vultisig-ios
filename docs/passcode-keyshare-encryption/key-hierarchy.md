# The key hierarchy

Two levels, and the separation between them is the reason changing a passcode is
cheap and the reason a 5-digit passcode is not the thing protecting the wallet.

```
   user types 5 digits
           │
           │  PBKDF2-SHA256, 600k iterations, 16-byte random salt
           ▼
   wrapping key (256 bit, never stored)
           │
           │  AES-GCM seals 32 bytes
           ▼
   ┌───────────────────────────────────────────┐
   │  wrapped data key   ← the ONLY persisted   │  Keychain item
   │  VLT\x02 ‖ salt ‖ nonce ‖ ct ‖ tag         │  (absent when no passcode)
   └───────────────────────────────────────────┘
           │
           │  unwrap on unlock; held in memory only
           ▼
   data key (256 random bits, CSPRNG, derived from nothing)
           │
           │  AES-GCM, one blob per share, fresh nonce each time
           ▼
   "vlt2:" + base64(VLT\x02 ‖ salt ‖ nonce ‖ ct ‖ tag)   ← KeyShare.keyshare
```

Constants live in `VaultCryptoEnvelope`: `keyLengthBytes = 32`,
`saltLength = 16`, `ivLength = 12`, `gcmTagBytes = 16`,
`pbkdf2Iterations = 600_000`. The `VLT\x02` blob format is shared with the
desktop client's vault backup, so one parser covers vault backups, sealed key
shares and the wrapped data key alike. The salt is meaningful only for the
password-derived payloads; raw-key callers still fill it with random bytes so
every blob has the same shape.

## Why the passcode never encrypts shares directly

Three separate reasons, all load-bearing:

1. **Changing a passcode is O(1).** Rewrap 32 bytes, write one Keychain item,
   done — **no key share is read or written**. The desktop client, which does
   encrypt shares under the passcode directly, has to re-encrypt every share of
   every vault for the same user action, which means it puts key material
   through a rewrite on a routine settings change. `changePasscode` here is
   `unlock → wrap → storeWrappedDataKey → rebind the biometric copy`, and the
   ciphertext on disk is byte-identical before and after. There is a test that
   asserts exactly that.

2. **A 5-digit passcode is ~16.6 bits.** However it is stretched, an attacker
   holding the Keychain blob can enumerate it. PBKDF2 at 600k iterations does
   not make the wrap strong — it buys a per-guess cost on the *in-app* path,
   which is what `PasscodeAttemptLimiter` is really enforcing. The thing
   actually protecting a share is the 256-bit data key, which is random and
   derived from nothing the user knows. If shares were sealed under a
   passcode-derived key, share strength would be passcode strength.

3. **Future indirection is free.** Per-vault keys (decoy vaults, say) slot in
   under the data key without touching the passcode layer at all.

## Why there is no unwrapped resting state

The Keychain holds the key **only** in passcode-wrapped form. It is in memory
only while the app is unlocked (`KeyshareKeySession`), and `lock()` forgets it.
Removing the passcode does not stash a clear key beside the shares — it opens
every share back to plaintext and deletes the wrapper.

That means there is no third place the key can be found, and no state in which a
share is sealed but reachable without the passcode. An earlier design did keep a
clear `keyshareDataKey` item; it is gone, and `PasscodeError.noDataKey` with it.
If you find a source describing one, you are reading a superseded document.

## Verification, and where it comes from

There is no separate stored "verification sample" to check a passcode against,
and there must not be — that would be an oracle. Every check is a GCM tag check:

| Question | Answered by |
|---|---|
| Is this the right passcode? | `unwrap` fails GCM ⇒ `KeyshareKeyStoreError.wrongPasscode` |
| Is this blob even a wrapped key? | `VaultCryptoEnvelope.parse` returns nil, or the plaintext is not 32 bytes ⇒ `malformedWrappedKey` (**not** a wrong passcode — see below) |
| Was this share sealed under the key I hold? | `open` succeeds |
| Did my seal actually work? | seal, then open, then compare to the original — the sweeper does this per share |

`malformedWrappedKey` is mapped to `PasscodeError.storageFailure` and
deliberately **not** counted as a failed attempt. Counting it would bury an
unrecoverable storage problem under a growing lockout and tell the user the
wrong thing.

## Reading a value tells you which kind it is

`AesGcmKeyshareCipher.sealedPrefix` is `"vlt2:"`. `:` is outside the base64
alphabet, so a sealed value can never be confused with a plaintext DKLS share
(base64) or a plaintext GG20 share (JSON). Detection is a pure function of the
value — nothing else has to be consulted, and re-sealing an already-sealed value
is a no-op rather than a corruption.

That property is what lets a store be half-swept and still work, and it is also
the property that makes the sweeper's third refusal necessary: a value that
`isSealed` says is sealed has *not* thereby been proved openable. See
[invariants](invariants.md#the-three-sweeper-refusals).

## The wrapped key is the whole of the persisted state

There is no "passcode is enabled" boolean anywhere. `PasscodeService.isSet` is a
read of the wrapped key, and `AppLockService.mode` (in `UserDefaults`) is a
*cache* of that fact which `KeyshareInstallReconciler` repairs in both
directions at launch. Deriving state from one source is what removes the class
of bug where two flags disagree.

Because the wrapper is that important, both of its mutations are verified:

- `storeWrappedDataKey` writes then reads back and compares bytes; anything
  other than `.present(sameBytes)` throws `persistenceFailed`. Encrypting
  against a key we cannot prove is durable is how shares get lost.
- `deleteWrappedDataKey` deletes then requires a **confirmed** `.absent`;
  `.unavailable` counts as failure, because a caller records a successful
  removal as done and never retries it.

The corollary of that second one is a trap in its own right and is written up in
[transitions](transitions.md#if-the-delete-fails): **a throw from
`deleteWrappedDataKey` does not prove the item survived.**

## The biometric copy

`BiometricUnlockStore` is an optional shortcut, never a replacement. It holds a
**second copy of the same data key** behind
`SecAccessControl(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet)`.
The passcode-wrapped copy is untouched and always works, so the shortcut can be
removed, invalidated or fail without costing anyone access.

`.biometryCurrentSet` rather than `.biometryAny`: the system destroys the item if
enrolled biometrics change, so enrolling a new face does not silently inherit
access to the wallet. `localizedFallbackTitle = ""` hides the fallback button,
but what actually prevents the *device* passcode from satisfying the read is the
access control — neither `.devicePasscode` nor `.userPresence` is requested, so a
biometric lockout fails rather than falling back. Someone who knows only the
device passcode must not reach a wallet the app passcode exists to protect.

### Why the copy is *bound* rather than *verified*

The stored blob is `SHA256(wrappedDataKey) ‖ dataKey`, and the digest is checked
before the key is ever adopted.

The direct check is unavailable: nothing in the unlock path can prove a stored
key opens anything. The wrapper cannot be unwrapped without the passcode — that
is the whole point — and an interrupted `setPasscode` can leave a store with no
sealed share to test against either.

The failure this closes is a fund-loss path. A copy surviving from a previous
install holds key **A** while the durable wrapper holds key **B**. Adopting A
would let the resume sweep that follows *every* app unlock seal every share
under a key no wrapper holds — orphaned on the next lock. Binding makes the
mismatch detectable up front, and the stale copy is removed rather than left to
fail again.

The digest leaks nothing (it digests a blob that already sits unprotected in the
same Keychain) and a collision would be cryptographic, since the wrapper carries
a random salt and nonce. Its one false negative — a crash between
`storeWrappedDataKey` and the rebind — costs the shortcut, never the passcode.

### Lifecycle

| Event | What happens to the copy |
|---|---|
| `setPasscode` | any leftover is deleted first, and a failure to delete **aborts the set** — a copy without a passcode behind it is a leftover, and it would report the shortcut as already enabled for a passcode the user is only now creating |
| `changePasscode` | rebound to the new wrapper. Writing the item never prompts for a face; only reading does, so this is silent. If it cannot be rebound it is removed, because a stale binding is refused at the next unlock anyway and leaving one advertises a shortcut the app will not honour |
| `disablePasscode` | removed **first**, before a single share moves — see [transitions](transitions.md#disablepasscode) |
| new app container | removed by `KeyshareInstallReconciler` along with the rest of the inherited material |
| enrolment changes | destroyed by the system |

One `Security` gotcha is baked into the type split and is easy to undo:
`BiometricKeychain.store` is a **pure `SecItemAdd`**, and the delete-first is
`BiometricUnlockStore.enable`'s job with a **search-only** query.
`SecItemDelete` takes a search query, so handing it the full add dictionary
(with `kSecValueData` and `kSecAttrAccessControl` in it) matches nothing, and the
add that follows answers `errSecDuplicateItem`. That silently broke rebinding
after a passcode change.
