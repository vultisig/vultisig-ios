//
//  SendDoneScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/08/2025.
//

import SwiftUI

struct SendDoneScreen: View {
    let vault: Vault
    let hash: String
    let chain: Chain
    let tx: SendTransaction
    
    @State var navigateToTransactionDetails = false
    
    let sendSummaryViewModel = SendSummaryViewModel()
    
    var body: some View {
        Screen(title: "done".localized) {
            SendCryptoDoneView(
                vault: vault,
                hash: hash,
                approveHash: nil,
                chain: chain,
                sendTransaction: tx,
                swapTransaction: nil,
                isSend: true,
                contentPadding: 0,
                navigateToTransactionDetails: $navigateToTransactionDetails
            )
        }
//        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToTransactionDetails) {
            SendCryptoSecondaryDoneView(
                input: SendCryptoContent(
                    coin: tx.coin,
                    amountCrypto: "\(tx.amount) \(tx.coin.ticker)",
                    amountFiat: tx.amountInFiat,
                    hash: hash,
                    explorerLink: Endpoint.getExplorerURL(chain: chain, txid: hash),
                    memo: tx.memo,
                    isSend: true,
                    fromAddress: tx.fromAddress,
                    toAddress: tx.toAddress,
                    fee: (tx.gasInReadable, sendSummaryViewModel.feesInReadable(tx: tx, vault: vault))
                ),
                onDone: {
                    tx.reset(coin: tx.coin)
                }
            )
        }
    }
}
