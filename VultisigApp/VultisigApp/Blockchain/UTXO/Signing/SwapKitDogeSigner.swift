//
//  SwapKitDogeSigner.swift
//  VultisigApp
//
//  Signs SwapKit's pre-built DOGE PSBT. Same wire as BTC at the framing
//  level — base64 PSBT with `meta.txType: "PSBT"` — but DOGE inputs are
//  legacy P2PKH (DOGE has no segwit), so we can't ride `BitcoinPsbtSigner`'s
//  BIP-143 path. Instead, parse the PSBT into a frozen
//  `BitcoinTransactionPlan` and let WalletCore's `TransactionCompiler`
//  sign through `CoinType.dogecoin` end-to-end (same path the native send
//  helper uses).
//
//  Wire shape observed at probe time (`DOGE.DOGE → ETH.USDC` via NEAR
//  Intents): the input map ships `PSBT_IN_NON_WITNESS_UTXO` (key `0x00`) —
//  the full prev-tx with its outputs. The shared signer accepts both
//  `NON_WITNESS_UTXO` and `WITNESS_UTXO` for robustness.
//
//  `tx_id` preservation: the frozen plan re-emits the exact inputs/outputs
//  SwapKit handed us, so the broadcast tx_id matches the one NEAR Intents
//  tracks the route by.
//

import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-doge-signer")

enum SwapKitDogeSignerError: Error, LocalizedError {
    case underlying(SwapKitLegacyP2PKHSignerError)

    var errorDescription: String? {
        switch self {
        case .underlying(let err): return err.errorDescription
        }
    }
}

enum SwapKitDogeSigner {

    /// Compute legacy ECDSA P2PKH sighashes for every input in the SwapKit
    /// DOGE PSBT. WalletCore handles the per-input preimage construction via
    /// `CoinType.dogecoin` + `BitcoinScript.buildPayToPublicKeyHash` (same
    /// path as the native DOGE send).
    static func preSigningHashes(payload: SwapKitSwapPayload) throws -> [String] {
        do {
            return try SwapKitLegacyP2PKHSigner.preSigningHashes(
                psbtBytes: payload.txPayload,
                coin: .dogecoin,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitDogeSignerError.underlying(err)
        }
    }

    /// Assemble the signed broadcast tx from the SwapKit PSBT and MPC
    /// signatures. ECDSA-DER signatures verified against per-input preimage
    /// hashes before `TransactionCompiler.compileWithSignatures` emits the
    /// final transaction.
    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        do {
            return try SwapKitLegacyP2PKHSigner.compileSignedTransaction(
                psbtBytes: payload.txPayload,
                coin: .dogecoin,
                signatures: signatures,
                pubKeyHex: pubKeyHex,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitDogeSignerError.underlying(err)
        }
    }

    /// Exposed for unit tests so the structural shape (input count, plan
    /// amount/change/fee, deposit scriptPubKey) can be pinned without going
    /// through MPC.
    static func buildSigningInput(payload: SwapKitSwapPayload) throws -> BitcoinSigningInput {
        do {
            return try SwapKitLegacyP2PKHSigner.buildSigningInput(
                psbtBytes: payload.txPayload,
                coin: .dogecoin,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitDogeSignerError.underlying(err)
        }
    }
}
