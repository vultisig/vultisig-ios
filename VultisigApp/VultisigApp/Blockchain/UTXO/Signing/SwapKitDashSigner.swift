//
//  SwapKitDashSigner.swift
//  VultisigApp
//
//  Signs SwapKit's pre-built DASH PSBT. Mirrors `SwapKitDogeSigner` /
//  `SwapKitBCHSigner` — DASH has no segwit (forked from Bitcoin pre-0.12.x),
//  every UTXO is legacy P2PKH, and we ride WalletCore's `TransactionCompiler`
//  via `CoinType.dash` through the shared `SwapKitLegacyP2PKHSigner`.
//
//  Wire-shape disclaimer: the DASH `/v3/swap` probe during the spike
//  returned `insufficientBalance` (test address empty), so the canonical
//  PSBT body wasn't directly observed. The signer is structured around the
//  strong DOGE / BCH analogues (same NEAR Intents pipeline, same P2PKH
//  legacy script type) and the shared helper accepts both NON_WITNESS_UTXO
//  and WITNESS_UTXO so whichever shape SwapKit ships works without a code
//  change.
//
//  If a future probe surfaces a non-PSBT wire shape (e.g. deposit-only with
//  `tx: null`), the DASH plan documented that path as the Cardano-style
//  fallback. The DOGE plan flagged the risk: NEAR Intents tracks routes by
//  tx_id, and a client-rebuilt tx would change the hash and break
//  tracking — so we ship the PSBT signer pre-emptively rather than the
//  deposit-only fallback. If `/v3/swap` returns a non-PSBT body, the
//  decoder fails closed (no `.dashPsbt` case selected, `unsupported`
//  surfaces).
//

import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-dash-signer")

enum SwapKitDashSignerError: Error, LocalizedError {
    case underlying(SwapKitLegacyP2PKHSignerError)

    var errorDescription: String? {
        switch self {
        case .underlying(let err): return err.errorDescription
        }
    }
}

enum SwapKitDashSigner {

    static func preSigningHashes(payload: SwapKitSwapPayload) throws -> [String] {
        do {
            return try SwapKitLegacyP2PKHSigner.preSigningHashes(
                psbtBytes: payload.txPayload,
                coin: .dash,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitDashSignerError.underlying(err)
        }
    }

    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        do {
            return try SwapKitLegacyP2PKHSigner.compileSignedTransaction(
                psbtBytes: payload.txPayload,
                coin: .dash,
                signatures: signatures,
                pubKeyHex: pubKeyHex,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitDashSignerError.underlying(err)
        }
    }

    /// Exposed for unit tests.
    static func buildSigningInput(payload: SwapKitSwapPayload) throws -> BitcoinSigningInput {
        do {
            return try SwapKitLegacyP2PKHSigner.buildSigningInput(
                psbtBytes: payload.txPayload,
                coin: .dash,
                targetAddress: payload.targetAddress
            )
        } catch let err as SwapKitLegacyP2PKHSignerError {
            throw SwapKitDashSignerError.underlying(err)
        }
    }
}
