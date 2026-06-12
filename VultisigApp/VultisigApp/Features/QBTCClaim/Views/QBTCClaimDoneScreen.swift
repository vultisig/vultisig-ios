//
//  QBTCClaimDoneScreen.swift
//  VultisigApp
//
//  QBTC-claim entry point onto the unified `DoneScreen`. Uses the
//  default token / detail / bottom-bar slots — claim looks identical
//  to Send except for the localized verb (`.claim` swaps "Transaction"
//  copy for "Claim" copy on the status header). Live status polling
//  works out of the box because the QBTC chain is already wired
//  through `ChainStatusConfig.config(for: .qbtc)`. Used by both the
//  initiator and (post-tx-hash propagation) the co-signer device.
//

import SwiftUI

struct QBTCClaimDoneScreen: View {
    let result: QBTCClaimRunResult
    let vault: Vault
    let btcCoin: Coin
    let qbtcCoin: Coin

    var body: some View {
        DoneScreen(
            input: payload,
            statusService: DoneStatusServiceFactory.qbtcClaim(
                result: result,
                qbtcCoin: qbtcCoin,
                vault: vault
            )
        )
    }

    private var payload: TransactionDonePayload {
        TransactionDonePayload(
            coin: qbtcCoin,
            amountCrypto: QBTCClaimAmountFormatter.formatQbtc(sats: result.totalSatsClaimed),
            amountFiat: "",
            hash: result.txHashHex,
            explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: .qbtc, txid: result.txHashHex),
            memo: "",
            isSend: true,
            fromAddress: btcCoin.address,
            toAddress: qbtcCoin.address,
            fee: FeeDisplay(crypto: "", fiat: ""),
            keysignPayload: nil,
            pubKeyECDSA: vault.pubKeyECDSA,
            verb: .claim
        )
    }
}
