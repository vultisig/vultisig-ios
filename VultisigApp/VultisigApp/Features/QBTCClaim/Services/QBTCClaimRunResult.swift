//
//  QBTCClaimRunResult.swift
//  VultisigApp
//
//  Result + phase value types for the QBTC claim orchestrator.
//

import Foundation

struct QBTCClaimRunResult: Equatable {
    /// Uppercase hex of `SHA256(TxRaw)`. Locally computed — does NOT come
    /// from the broadcast response. See `QBTCHelper.assembleClaimTxRaw`.
    let txHashHex: String
    /// Total satoshis selected across the claim's UTXOs.
    let totalSatsClaimed: UInt64
}

/// Phase of the QBTC claim flow. Drives the screen's main content.
/// `Equatable` so SwiftUI can `onChange` on transitions and tests can
/// assert exact transition sequences.
enum QBTCClaimPhase: Equatable {
    case idle
    case signingBTC
    case generatingProof
    case signingMLDSA
    case broadcasting
    case done(QBTCClaimRunResult)
    /// Failure carries a user-visible message; the screen returns to
    /// UTXO selection with selection intact and shows this in a banner.
    case failed(String)
}

/// Inputs needed to run a claim. Constructed by the screen ViewModel
/// after the user has confirmed a UTXO selection and supplied their
/// FastVault password.
struct QBTCClaimRunInput {
    let vault: Vault
    /// The vault's Bitcoin coin — provides `address`, `hexPublicKey`
    /// (compressed 33-byte secp256k1), and the BTC derivation path.
    let btcCoin: Coin
    /// The vault's QBTC coin — provides the bech32 claimer address and
    /// the MLDSA pubkey hex (`hexPublicKey`).
    let qbtcCoin: Coin
    /// Selected UTXOs to include in the claim. 1..50.
    let utxos: [ClaimableUtxo]
    /// FastVault password (collected once via the password modal).
    let fastVaultPassword: String
}
