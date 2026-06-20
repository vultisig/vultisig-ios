//
//  QBTCClaimConfig.swift
//  VultisigApp
//
//  Single source of truth for QBTC claim constants.
//  Mirrors the SDK + windows references — keep these aligned.
//

import Foundation

/// Single source of truth for the QBTC Cosmos chain-id, shared by the claim,
/// staking, and signing paths. QBTC reached mainnet, so the chain-id is `qbtc`
/// (the prior `qbtc-testnet` value is no longer used in production). NOTE: this
/// is the chain-**id**, distinct from the bech32 HRP / denom / logo string which
/// is also `"qbtc"` but unrelated and defined elsewhere.
enum QBTCChain {
    static let chainID = "qbtc"
}

enum QBTCClaimConfig {
    static let chainId = QBTCChain.chainID

    static let msgClaimWithProofTypeURL = "/qbtc.qbtc.v1.MsgClaimWithProof"
    static let mldsaPubKeyTypeURL = "/cosmos.crypto.mldsa.PubKey"

    static let gasLimit: UInt64 = 300_000
    static let maxClaimUtxos = 50

    static let mldsaDerivePath = "m"

    /// The proof service expects `signature_r` zero-padded to this byte width.
    /// 24 (not 32) — matches the proof circuit's witness size. Easy to miss.
    static let proofServiceRBytes = 24
    /// The proof service expects `signature_s` zero-padded to this byte width.
    static let proofServiceSBytes = 32

    /// Wall-clock budget for proof generation. The chain's PLONK prover is slow.
    static let proofServiceTimeoutSeconds: TimeInterval = 300

    /// ASCII domain-separation tags for the claim message hash.
    /// MUST match `x/qbtc/zk/message.go` server-side, byte-for-byte.
    static let domainTagPrefix = "ecdsa-hash160:"
    static let domainTagSuffix = "qbtc-claim-v1"

    /// The first 8 bytes of `SHA256(chainId)` are used in the message hash.
    /// Truncation, not full digest — this is the easy-to-miss one.
    static let chainIdHashPrefixBytes = 8
}
