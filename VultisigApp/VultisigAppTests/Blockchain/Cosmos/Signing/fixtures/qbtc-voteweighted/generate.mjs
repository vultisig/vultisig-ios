// generate.mjs — independent cosmjs encoder for the QBTC weighted-vote vector.
//
// Emits the expected bytes/hashes used by `QBTCVoteWeightedVectorFixture.swift`
// so the iOS byte-equality test is a NON-CIRCULAR cross-platform gate: the
// vectors come from the cosmjs codec family a Windows/SDK peer uses, NOT from
// iOS's own hand-rolled encoder.
//
// Encoding strategy (mirrors what a cosmjs-based peer signs):
//   - MsgVoteWeighted          -> cosmjs-types `cosmos/gov/v1beta1/tx`
//   - TxBody / AuthInfo / Fee /
//     SignerInfo / ModeInfo /
//     SignDoc / TxRaw          -> cosmjs-types `cosmos/tx/v1beta1/tx`
//   - signer public key Any    -> cosmjs-types `google/protobuf/any`, with the
//                                 custom `/cosmos.crypto.mldsa.PubKey` value
//                                 encoded by hand (proto field 1 = bytes), since
//                                 cosmjs has no codec for the ML-DSA key type.
//
// Run:  npm install && node generate.mjs
// (or, without network: node against vultisig-windows's installed cosmjs --
//  see README.md.)

import { sha256 } from '@cosmjs/crypto'
import { fromHex, toBase64, toHex } from '@cosmjs/encoding'
import { MsgVoteWeighted } from 'cosmjs-types/cosmos/gov/v1beta1/tx'
import {
  AuthInfo,
  Fee,
  ModeInfo,
  SignDoc,
  SignerInfo,
  TxBody,
  TxRaw,
} from 'cosmjs-types/cosmos/tx/v1beta1/tx'
import { SignMode } from 'cosmjs-types/cosmos/tx/signing/v1beta1/signing'
import { Any } from 'cosmjs-types/google/protobuf/any'

// ---------------------------------------------------------------------------
// Semantic inputs (see QBTCVoteWeightedVectorFixture.swift)
// ---------------------------------------------------------------------------
const VOTER = 'qbtc1voter00000000000000000000000000000000'
const CHAIN_ID = 'qbtc-testnet'
const PROPOSAL_ID = 42n
const ACCOUNT_NUMBER = 100n
const SEQUENCE = 7n
const FEE_DENOM = 'qbtc' // verified from the AuthInfo bytes (not "uqbtc")
const FEE_AMOUNT = '800'
const GAS_LIMIT = 300000n
const MLDSA_PUBKEY = new Uint8Array(1312).fill(0xab)
const MLDSA_PUBKEY_TYPE_URL = '/cosmos.crypto.mldsa.PubKey'
const VOTEWEIGHTED_TYPE_URL = '/cosmos.gov.v1beta1.MsgVoteWeighted'
// Fake signature — the TxRaw assertion is about encoding, not crypto.
const FAKE_SIGNATURE = fromHex('deadbeef01020304')
// TxBody.memo is empty: the QBTC_VOTEW UI memo carries the vote into the
// MsgVoteWeighted message; it is NOT re-emitted into TxBody.memo (confirmed by
// decoding the prior fixture bodyBytes, and by iOS `buildTxBody` setting
// `memo = nil` for the vote path).
const MEMO = ''

// --- minimal varint + length-delimited proto helpers (for the custom Any) ---
const varint = value => {
  let v = BigInt(value)
  const out = []
  while (v > 0x7fn) {
    out.push(Number((v & 0x7fn) | 0x80n))
    v >>= 7n
  }
  out.push(Number(v))
  return Uint8Array.from(out)
}
const lenDelimited = (fieldNumber, data) =>
  concat(varint(BigInt(fieldNumber << 3) | 2n), varint(data.length), data)
const concat = (...chunks) => {
  const total = chunks.reduce((n, c) => n + c.length, 0)
  const out = new Uint8Array(total)
  let off = 0
  for (const c of chunks) {
    out.set(c, off)
    off += c.length
  }
  return out
}

// MsgVoteWeighted body via cosmjs.
const msgVoteWeighted = MsgVoteWeighted.encode(
  MsgVoteWeighted.fromPartial({
    proposalId: PROPOSAL_ID,
    voter: VOTER,
    options: [
      { option: 1, weight: '0.700000000000000000' }, // YES
      { option: 2, weight: '0.300000000000000000' }, // ABSTAIN
    ],
  })
).finish()

// TxBody via cosmjs (message wrapped in google.protobuf.Any by TxBody.encode).
const bodyBytes = TxBody.encode(
  TxBody.fromPartial({
    messages: [Any.fromPartial({ typeUrl: VOTEWEIGHTED_TYPE_URL, value: msgVoteWeighted })],
    memo: MEMO,
  })
).finish()

// ML-DSA pubkey Any: cosmjs has no codec for this custom key type, so encode
// the inner PubKey{ field 1 = bytes } by hand, then wrap via cosmjs Any.
const pubKeyMsg = lenDelimited(1, MLDSA_PUBKEY)
const pubKeyAny = Any.fromPartial({ typeUrl: MLDSA_PUBKEY_TYPE_URL, value: pubKeyMsg })

const authInfoBytes = AuthInfo.encode(
  AuthInfo.fromPartial({
    signerInfos: [
      SignerInfo.fromPartial({
        publicKey: pubKeyAny,
        modeInfo: ModeInfo.fromPartial({ single: { mode: SignMode.SIGN_MODE_DIRECT } }),
        sequence: SEQUENCE,
      }),
    ],
    fee: Fee.fromPartial({
      amount: [{ denom: FEE_DENOM, amount: FEE_AMOUNT }],
      gasLimit: GAS_LIMIT,
    }),
  })
).finish()

const signDocBytes = SignDoc.encode(
  SignDoc.fromPartial({
    bodyBytes,
    authInfoBytes,
    chainId: CHAIN_ID,
    accountNumber: ACCOUNT_NUMBER,
  })
).finish()

const txRawBytes = TxRaw.encode(
  TxRaw.fromPartial({
    bodyBytes,
    authInfoBytes,
    signatures: [FAKE_SIGNATURE],
  })
).finish()

const out = {
  bodyBytesB64: toBase64(bodyBytes),
  authInfoBytesB64: toBase64(authInfoBytes),
  signDocSHA256Hex: toHex(sha256(signDocBytes)),
  txRawSHA256HexUpper: toHex(sha256(txRawBytes)).toUpperCase(),
}

console.log(JSON.stringify(out, null, 2))
