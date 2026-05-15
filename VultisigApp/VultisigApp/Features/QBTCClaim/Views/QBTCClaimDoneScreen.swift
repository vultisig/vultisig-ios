//
//  QBTCClaimDoneScreen.swift
//  VultisigApp
//
//  Router-managed success screen for the QBTC claim flow. Reuses the
//  Send done-content primitive (`SendCryptoDoneContentView`) with the
//  `.claim` verb so the layout — status header, tx-hash row with
//  explorer link, transaction-details route, and "Done" CTA — matches
//  the Send/Swap done experience exactly. Used by both the initiator
//  and (post-tx-hash propagation) the co-signer device.
//

import SwiftUI

struct QBTCClaimDoneScreen: View {
    let result: QBTCClaimRunResult
    let vault: Vault
    let btcCoin: Coin
    let qbtcCoin: Coin

    @State private var showAlert: Bool = false

    var body: some View {
        Screen {
            ZStack {
                Background()
                SendCryptoDoneContentView(
                    input: content,
                    verb: .claim,
                    showAlert: $showAlert
                )
            }
            .overlay(PopupCapsule(text: "hashCopied", showPopup: $showAlert))
        }
        .screenTitle("done".localized)
        .screenBackButtonHidden()
    }

    private var content: SendCryptoContent {
        SendCryptoContent(
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
            pubKeyECDSA: vault.pubKeyECDSA
        )
    }
}
