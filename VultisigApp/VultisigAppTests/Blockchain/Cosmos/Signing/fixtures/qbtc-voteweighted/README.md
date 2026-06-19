# QBTC weighted-vote cross-platform vector generator

`generate.mjs` is the **independent, external source of truth** for the
expected bytes/hashes in `QBTCVoteWeightedVectorFixture.swift`. It encodes the
QBTC governance `MsgVoteWeighted` signing flow using the **cosmjs** codec family
(`cosmjs-types` + `@cosmjs/crypto`/`@cosmjs/encoding`) — the same codecs a
Windows/SDK peer uses — so the iOS byte-equality test
(`QBTCVoteWeightedByteEqualityTests`) is a genuine cross-platform gate rather
than a self-referential lock on iOS's own hand-rolled encoder.

## What it encodes

| Component | Encoder |
|-----------|---------|
| `MsgVoteWeighted` | `cosmjs-types/cosmos/gov/v1beta1/tx` |
| `TxBody` / `AuthInfo` / `Fee` / `SignerInfo` / `ModeInfo` / `SignDoc` / `TxRaw` | `cosmjs-types/cosmos/tx/v1beta1/tx` |
| signer public-key `Any` | `cosmjs-types/google/protobuf/any` (the inner `/cosmos.crypto.mldsa.PubKey` value — proto field 1 = 1312 bytes — is encoded by hand, since cosmjs has no codec for this post-quantum key type) |

Semantic inputs are documented at the top of `generate.mjs` and mirror the
fixture: proposal 42, voter `qbtc1voter0…`, YES=0.7 / ABSTAIN=0.3 (18-dec
LegacyDec), ML-DSA-44 pubkey `0xAB × 1312`, chain `qbtc-testnet`,
account 100, sequence 7, fee `800 qbtc`, gas 300000, SIGN_MODE_DIRECT, fake
signature `deadbeef01020304`.

Two findings worth recording (verified by decoding the prior fixture bytes):

- **`TxBody.memo` is empty.** The `QBTC_VOTEW:…` UI memo carries the vote into
  the `MsgVoteWeighted` message; it is NOT re-emitted into `TxBody.memo`.
- **The fee denom is `qbtc`** (4 bytes), not `uqbtc`. The earlier fixture
  comment said "800 uqbtc"; the actual AuthInfo bytes encode denom `qbtc`.

## How to run

```bash
cd VultisigApp/VultisigAppTests/Blockchain/Cosmos/Signing/fixtures/qbtc-voteweighted
npm install      # pinned: cosmjs-types 0.11.0, @cosmjs/crypto + @cosmjs/encoding 0.39.0
node generate.mjs
```

Prints JSON with `bodyBytesB64`, `authInfoBytesB64`, `signDocSHA256Hex`,
`txRawSHA256HexUpper`. Copy these verbatim into the fixture's literals.

If `npm install` is blocked (no network), run against vultisig-windows's
already-installed cosmjs, e.g. via a temporary `node_modules` symlink — the
pinned versions above match what that repo vendors.

`node_modules/` is git-ignored; `package-lock.json` is committed so the run is
reproducible.

## When to regenerate

Re-run and update the fixture whenever the QBTC weighted-vote signing recipe
changes (message shape, AuthInfo layout, SignDoc field order, fee/denom
defaults). The iOS test then proves iOS still matches the cosmjs output.
