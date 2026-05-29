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
                )
            )
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
