//
//  QBTCVoteWeightedVectorFixture.swift
//  VultisigAppTests
//
//  GENERATED FIXTURE — DO NOT HAND-EDIT THE BASE64/HASH LITERALS.
//
//  Cross-platform signing vector for the QBTC governance MsgVoteWeighted
//  path, the weighted-vote analogue of `QBTCCosignVector`. The expected
//  bytes are DERIVED FROM THE PROTO / cosmjs CONTRACT — proto3 wire encoding
//  of `/cosmos.gov.v1beta1.MsgVoteWeighted` (field 1 proposal_id, field 2
//  voter, repeated field 3 WeightedVoteOption{1 option, 2 weight}), wrapped
//  in the same Any / TxBody / AuthInfo / SignDoc / TxRaw recipe as the
//  single-vote vector (same ML-DSA-44 pubkey 0xAB x 1312, default fee 800
//  uqbtc, gas_limit 300000) — NOT from iOS's own output. So the assertions
//  pin that iOS's hand-rolled `buildMsgVoteWeighted` agrees byte-for-byte
//  with what a cosmjs-based peer would sign.
//
//  PROVENANCE CAVEAT (tracked follow-up): unlike the single-vote cosign
//  vector — whose AuthInfo/SignDoc bytes were recorded from the Windows/SDK
//  (cosmjs) encoder in vultisig-windows — these weighted-vote literals were
//  NOT yet regenerated from a committed external script/recording. The body
//  encoding is canonical proto3 for `/cosmos.gov.v1beta1.MsgVoteWeighted`
//  (cosmjs uses the same registry codec, see vultisig-windows
//  `messageRegistry.ts`), so the SHAPE matches the contract; but until these
//  bytes are reproduced from an external cosmjs/proto run, the byte-equality
//  test is only a *regression* guard (it locks the current encoder output) and
//  does NOT independently prove cross-platform agreement. Regenerate from the
//  cosmjs encoder to make the gate non-circular.
//
//  Inputs:
//    voter        = "qbtc1voter00000000000000000000000000000000"
//    mldsaPubKey  = 0xAB x 1312
//    chainId      = "qbtc-testnet"
//    proposalId   = 42
//    options      = YES=0.7, ABSTAIN=0.3  (canonical 18-dec LegacyDec strings)
//    sequence     = 7, accountNumber = 100
//

enum QBTCVoteWeightedVector {
    static let voter = "qbtc1voter00000000000000000000000000000000"
    static let mldsaPubKeyHex = String(repeating: "ab", count: 1312)
    static let chainID = "qbtc-testnet"

    /// The memo the weighted-vote UI emits for proposal 42, YES=0.7 ABSTAIN=0.3.
    static let memo = "QBTC_VOTEW:42:YES=0.7,ABSTAIN=0.3"

    static let bodyBytesB64 = "CokBCiMvY29zbW9zLmdvdi52MWJldGExLk1zZ1ZvdGVXZWlnaHRlZBJiCCoSKnFidGMxdm90ZXIwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMBoYCAESFDAuNzAwMDAwMDAwMDAwMDAwMDAwGhgIAhIUMC4zMDAwMDAwMDAwMDAwMDAwMDA="
    static let authInfoBytesB64 = "Cs4KCsMKChsvY29zbW9zLmNyeXB0by5tbGRzYS5QdWJLZXkSowoKoAqrq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urEgQKAggBGAcSEQoLCgRxYnRjEgM4MDAQ4KcS"
    static let signDocSHA256Hex = "ccfd8e7c6455ce8fc4ae9918fdc83b7a1847e2b04082d2a69ca5ee7ce230af50"

    static let signatureHex = "deadbeef01020304"
    static let txRawSHA256HexUpper = "CCA1FCB63FB842B9C00DCF932D261E9B666AFC5E1F71BAE303E7493F3439756C"
}
