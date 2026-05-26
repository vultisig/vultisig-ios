//
//  TransactionHistoryRecording.swift
//  VultisigApp
//
//  Unified entry point for tx-history recording from the done screens.
//  Pre-refactor each Done view called its own recorder method
//  (`recordSend` on Send, `recordSwap` + `recordApprove` + tracking-attach
//  on Swap, `recordFromKeysignPayload` on cosigner) with slightly
//  different shapes. This consolidates the dispatch in one helper that
//  the unified `DoneScreen` triggers on appear.
//
//  Each branch still routes through the underlying
//  `TransactionHistoryRecorder.shared` methods — no behaviour change.
//

import Foundation
import SwiftData

enum TransactionHistoryRecording {

    /// Records the send-style transaction reflected in `payload` to tx
    /// history. No-op when the payload doesn't carry a vault
    /// `pubKeyECDSA` (e.g. previews), when the hash is empty, or when
    /// the verb is `.claim` (QBTC has no tx-history schema yet).
    ///
    /// Swap-side flows pre-record via `recordSwap` + `recordApprove`
    /// from their screen layer (they carry from/to coin pairs we don't
    /// surface on the unified payload). Cosigner paths with a
    /// `KeysignPayload` are dispatched here via
    /// `recordFromKeysignPayload` so the cosigner's swap-branch gets
    /// captured too.
    @MainActor
    static func record(payload: TransactionDonePayload) {
        guard payload.pubKeyECDSA.isNotEmpty else { return }
        guard payload.hash.isNotEmpty else { return }

        // Cosigner: the full `KeysignPayload` carries the swap-or-send
        // discriminator + amounts. Delegate to the recorder helper.
        if let keysignPayload = payload.keysignPayload,
           keysignPayload.swapPayload != nil {
            guard let vault = lookupVault(pubKeyECDSA: payload.pubKeyECDSA) else { return }
            TransactionHistoryRecorder.shared.recordFromKeysignPayload(
                txHash: payload.hash,
                approveTxHash: nil,
                vault: vault,
                keysignPayload: keysignPayload
            )
            return
        }

        // QBTC claim opts out — no tx-history schema for claims today.
        guard payload.verb != .claim else { return }

        TransactionHistoryRecorder.shared.recordSend(
            txHash: payload.hash,
            pubKeyECDSA: payload.pubKeyECDSA,
            coin: payload.coin,
            amountCrypto: payload.amountCrypto,
            amountFiat: payload.amountFiat,
            fromAddress: payload.fromAddress,
            toAddress: payload.toAddress,
            feeCrypto: payload.fee.crypto,
            feeFiat: payload.fee.fiat,
            chain: payload.coin.chain,
            explorerLink: payload.explorerLink
        )
    }

    @MainActor
    private static func lookupVault(pubKeyECDSA: String) -> Vault? {
        guard let modelContext = Storage.shared.modelContext else { return nil }
        let descriptor = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == pubKeyECDSA })
        return (try? modelContext.fetch(descriptor))?.first
    }
}
