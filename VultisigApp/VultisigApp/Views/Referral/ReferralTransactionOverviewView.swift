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
    @State var navigateToHome: Bool = false
        
    var body: some View {
        Screen {
            SendCryptoDoneContentView(
                input: SendCryptoContent(
                    coin: sendTx.coin,
                    amountCrypto: "\(sendTx.amount) \(sendTx.coin.ticker)",
                    amountFiat: sendTx.amountInFiat,
                    hash: hash,
                    explorerLink: "https://thorchain.net/tx/\(hash)",
                    memo: sendTx.memo,
                    fromAddress: sendTx.fromAddress,
                    toAddress: sendTx.toAddress,
                    fee: (sendTx.gasInReadable, referralViewModel.totalFeeFiat)
                ),
                showAlert: .constant(false)
            ) {
                navigateToHome = true
            }
        }
        .onLoad {
            setData()
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToHome) {
            HomeView()
        }
    }
    
    private func setData() {
        if !isEdit {
            referralViewModel.savedGeneratedReferralCode = referralViewModel.referralCode
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
