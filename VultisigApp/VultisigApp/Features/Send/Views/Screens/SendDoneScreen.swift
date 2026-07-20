//
//  SendDoneScreen.swift
//  VultisigApp
//
//  Send-flow entry point onto the unified `DoneScreen`. Builds the
//  `TransactionDonePayload` from the live `SendTransaction` + tx hash
//  and uses the default token / detail / bottom-bar slots (coin
//  display, hash row + secondary disclosure, single "Done" CTA).
//
//  Status header is driven by `ChainPoller` (the per-chain RPC poller
//  every other Send/QBTC/non-SwapKit-swap flow uses), wired via
//  `DoneStatusServiceFactory.send`.
//

import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "send-done-screen")

struct SendDoneScreen: View {
    let vault: Vault
    let hash: String
    let chain: Chain
    let tx: SendTransaction?
    let keysignPayload: KeysignPayload?

    @Query private var vaults: [Vault]
    @Query private var addressBookItems: [AddressBookItem]

    @StateObject private var sendSummaryViewModel = SendSummaryViewModel()

    @State private var didRecordCancelBroadcast = false
    private let limitStorage = LimitOrderStorageService()

    var body: some View {
        if let tx {
            DoneScreen(
                input: payload(for: tx),
                statusService: DoneStatusServiceFactory.send(
                    txHash: hash,
                    chain: chain,
                    tx: tx,
                    vault: vault
                ),
                navigationTitle: "overview".localized
            )
            .onAppear { recordCancelBroadcastIfNeeded(tx: tx) }
        }
    }

    /// Attribute a CONFIRMED cancel broadcast back to the order it cancels.
    ///
    /// Guarded on a non-empty hash, which is what separates "the ceremony
    /// finished" from "the transaction actually went out" — the same guard
    /// `SwapDoneScreen` uses before persisting a placed order. A failed or
    /// abandoned keysign never reaches here with a hash, so the order is left
    /// resting, which is correct.
    ///
    /// Idempotent via `didRecordCancelBroadcast`: this screen can re-appear.
    @MainActor
    private func recordCancelBroadcastIfNeeded(tx: SendTransaction) {
        guard !didRecordCancelBroadcast,
              let context = tx.limitCancelContext,
              !hash.isEmpty else { return }
        didRecordCancelBroadcast = true
        do {
            try limitStorage.recordCancelBroadcast(of: context.orderId, txHash: hash, in: vault)
        } catch {
            // Non-fatal: the cancel is already on-chain. Worst case the order
            // later reads "Refunded" instead of "Cancelled" — wrong label, right
            // outcome — so this must not surface as an error over a successful
            // broadcast.
            logger.warning("Failed to record cancel broadcast: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func payload(for tx: SendTransaction) -> TransactionDonePayload {
        TransactionDonePayload(
            coin: tx.coin,
            amountCrypto: "\(tx.amount) \(tx.coin.ticker)",
            amountFiat: tx.amountInFiat,
            hash: hash,
            explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: chain, txid: hash),
            memo: tx.memo,
            isSend: true,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            toAlias: SendAddressResolver.resolveAlias(
                address: tx.toAddress,
                coinMeta: tx.coin.toCoinMeta(),
                ensLabel: tx.toAddressLabel,
                vaults: vaults,
                addressBookItems: addressBookItems
            ),
            fee: FeeDisplay(crypto: tx.gasInReadable, fiat: sendSummaryViewModel.feesInReadable(tx: tx)),
            keysignPayload: keysignPayload,
            pubKeyECDSA: vault.pubKeyECDSA
        )
    }
}
