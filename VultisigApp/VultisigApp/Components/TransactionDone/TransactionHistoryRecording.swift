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
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.vultisig.app", category: "tx-history-recorder")

enum TransactionHistoryRecording {

    /// Records the send-style transaction reflected in `payload` to tx
    /// history. No-op when the payload doesn't carry a vault
    /// `pubKeyECDSA` (e.g. previews), when the hash is empty, or when
    /// the verb is `.claim` (QBTC has no tx-history schema yet).
    ///
    /// Swap-side flows pre-record via `recordSwap` + `recordApprove`
    /// from their screen layer (they carry from/to coin pairs we don't
    /// surface on the unified payload) — those payloads ship with
    /// `isSend == false` and no `keysignPayload`, so this helper skips
    /// them to avoid double-counting. Cosigner paths with a
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
           Self.routesThroughKeysignRecorder(keysignPayload) {
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

        // Swap initiator: records via `recordSwap` + `recordApprove`
        // in its own screen layer. Skip here to avoid double-counting.
        guard payload.isSend || payload.keysignPayload != nil else { return }

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

    /// Whether a cosigner payload must be recorded via
    /// `recordFromKeysignPayload` rather than the plain `recordSend` fallback.
    ///
    /// A swap payload is the obvious trigger. A LIMIT ORDER qualifies even
    /// without one: a native-source (`RUNE`/`BTC`/…) order is a plain deposit
    /// whose `=<` memo is the entire order, so `swapPayload == nil`. Routed to
    /// `recordSend` it becomes a send row carrying no tracking metadata —
    /// missing from the Limit Orders tab, and left to the native poller, which
    /// reports the order Successful the moment the inbound deposit confirms.
    /// The memo is the only evidence a co-signer has that this is an order at
    /// all.
    ///
    /// Pure and `static` so the routing can be pinned by tests: the recorder it
    /// guards is a `private init()` singleton that writes to SwiftData, so the
    /// wired path itself isn't reachable from a unit test.
    static func routesThroughKeysignRecorder(_ keysignPayload: KeysignPayload) -> Bool {
        keysignPayload.swapPayload != nil || isLimitSwapMemo(keysignPayload.memo)
    }

    @MainActor
    private static func lookupVault(pubKeyECDSA: String) -> Vault? {
        guard let modelContext = Storage.shared.modelContext else {
            logger.error("Cannot lookup vault: modelContext unavailable")
            return nil
        }
        let descriptor = FetchDescriptor<Vault>(predicate: #Predicate { $0.pubKeyECDSA == pubKeyECDSA })
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            logger.error("Vault lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
