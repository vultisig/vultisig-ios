//
//  SwapKitBCHSigner.swift
//  VultisigApp
//
//  Signs SwapKit's pre-built BCH PSBT. Mirrors `SwapKitDogeSigner` — BCH
//  has no segwit, every UTXO is legacy P2PKH, and we ride WalletCore's
//  `TransactionCompiler` via `CoinType.bitcoinCash`.
//
//  BCH-specific quirk: the chain uses a BIP-143-style sighash algorithm
//  (the 2017 fork's reproducible-replay-protection design) but the digest
//  commits to the legacy `scriptCode` and the hash-type byte sets
//  `SIGHASH_FORKID` (`0x40`) alongside `SIGHASH_ALL`. WalletCore handles
//  this transparently: `BitcoinScript.hashTypeForCoin(.bitcoinCash)`
//  returns the right value and `TransactionCompiler.preImageHashes` uses
//  the BCH-flavoured preimage construction. Same path the native BCH send
//  helper rides.
//
//  Address-format quirk: SwapKit may echo CashAddr-prefixed
//  (`bitcoincash:q…`), bare CashAddr (`q…`), or legacy Base58 (`1…`).
//  WalletCore tolerates all three for `BitcoinScript.lockScriptForAddress`,
//  but we don't touch addresses here — the frozen plan operates on
//  scriptPubKey bytes lifted from the PSBT directly.
//
//  Wire-shape disclaimer: every `/v3/swap` probe for BCH during the spike
//  returned `failedToRetrieveBalance` (upstream NEAR Intents balance
//  indexer failure). The signer is structured around the strong DOGE
//  analogue (legacy P2PKH PSBT with NON_WITNESS_UTXO) and the shared
//  legacy-P2PKH helper accepts both NON_WITNESS_UTXO and WITNESS_UTXO so
//  whichever shape SwapKit actually ships works without a code change.
//

import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-bch-signer")

enum SwapKitBCHSignerError: Error, LocalizedError {
    case underlying(SwapKitLegacyP2PKHSignerError)

    var errorDescription: String? {
        switch self {
        case .underlying(let err): return err.errorDescription
        }
    }
}

enum SwapKitBCHSigner {

    /// Compute BCH preimage hashes (BIP-143-style with SIGHASH_FORKID) for
    /// every input. WalletCore handles the per-input preimage construction
    /// via `CoinType.bitcoinCash`.
    static func preSigningHashes(payload: SwapKitSwapPayload) throws -> [String] {
        do {
            return try SwapKitLegacyP2PKHSigner.preSigningHashes(
                psbtBytes: payload.txPayload,
                coin: .bitcoinCash,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitBCHSignerError.underlying(err)
        }
    }

    /// Assemble the signed broadcast tx. ECDSA-DER signatures verified
    /// against per-input preimage hashes before
    /// `TransactionCompiler.compileWithSignatures` emits the final tx.
    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        do {
            return try SwapKitLegacyP2PKHSigner.compileSignedTransaction(
                psbtBytes: payload.txPayload,
                coin: .bitcoinCash,
                signatures: signatures,
                pubKeyHex: pubKeyHex,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitBCHSignerError.underlying(err)
        }
    }

    /// Exposed for unit tests.
    static func buildSigningInput(payload: SwapKitSwapPayload) throws -> BitcoinSigningInput {
        do {
            return try SwapKitLegacyP2PKHSigner.buildSigningInput(
                psbtBytes: payload.txPayload,
                coin: .bitcoinCash,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitBCHSignerError.underlying(err)
        }
    }
}
