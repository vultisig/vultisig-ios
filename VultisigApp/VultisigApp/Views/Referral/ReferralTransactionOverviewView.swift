//
//  ReferralTransactionOverviewView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-28.
//

import SwiftUI
import RiveRuntime

struct ReferralTransactionOverviewView: View {
    let hash: String
    let sendTx: SendTransaction
    let isEdit: Bool
    @ObservedObject var referralViewModel: ReferralViewModel

    var body: some View {
        Screen {
            SendCryptoDoneContentView(
                input: SendCryptoContent(
                    coin: sendTx.coin,
                    amountCrypto: "\(sendTx.amount) \(sendTx.coin.ticker)",
                    amountFiat: sendTx.amountInFiat,
                    hash: hash,
                    explorerLink: Endpoint.getExplorerURL(chain: sendTx.coin.chain, txid: hash),
                    memo: sendTx.memo,
                    isSend: false,
                    fromAddress: sendTx.fromAddress,
                    toAddress: sendTx.toAddress,
                    fee: FeeDisplay(crypto: sendTx.gasInReadable, fiat: referralViewModel.totalFeeFiat),
                    keysignPayload: nil
                ),
                showAlert: .constant(false)
            )
        }
        .onLoad {
            setData()
        }
        .navigationBarBackButtonHidden(true)
    }

    private func setData() {
        if !isEdit {
            referralViewModel.updateReferralCode(code: referralViewModel.referralCode)
        }
    }
}

#Preview {
    ReferralTransactionOverviewView(
        hash: "",
        sendTx: SendTransaction(),
        isEdit: false,
        referralViewModel: ReferralViewModel()
    )
}
