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

import SwiftData
import SwiftUI

struct SendDoneScreen: View {
    let vault: Vault
    let hash: String
    let chain: Chain
    let tx: SendTransaction?
    let keysignPayload: KeysignPayload?

    @Query private var vaults: [Vault]
    @Query private var addressBookItems: [AddressBookItem]

    @StateObject private var sendSummaryViewModel = SendSummaryViewModel()

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
        }
    }

    private func payload(for tx: SendTransaction) -> TransactionDonePayload {
        // A limit-order cancel is not a send. Its own verb reports on the
        // TRANSACTION — which is all this screen can honestly speak to — and
        // says in as many words that the order stays open until the queue
        // confirms it closed. The generic "Transaction successful" would be
        // read as "your order is cancelled", which is precisely the claim
        // THORChain has not made yet.
        let isCancel = tx.limitCancelContext != nil
        return TransactionDonePayload(
            coin: tx.coin,
            amountCrypto: "\(tx.amount) \(tx.coin.ticker)",
            amountFiat: tx.amountInFiat,
            hero: LimitOrderCancelPresentation.hero(for: tx),
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
            pubKeyECDSA: vault.pubKeyECDSA,
            verb: isCancel ? .cancelLimitOrder : .send
        )
    }
}
