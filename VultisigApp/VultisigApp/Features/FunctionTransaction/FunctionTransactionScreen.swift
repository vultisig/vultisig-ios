//
//  FunctionTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct FunctionTransactionScreen: View {
    let vault: Vault
    let transactionType: FunctionTransactionType
    
    @State private var sendTx: SendTransaction?
    @State private var navigateToVerify: Bool = false
    
    var body: some View {
        ZStack {
            switch transactionType {
            case .bond(let node):
                if let runeCoin = vault.runeCoin {
                    BondTransactionScreen(
                        viewModel: BondTransactionViewModel(
                            coin: runeCoin,
                            vault: vault,
                            initialBondAddress: node
                        ),
                        onVerify: onVerify
                    )
                }
            case .unbond:
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $navigateToVerify) {
            if let sendTx {
                FunctionCallRouteBuilder().buildVerifyScreen(tx: sendTx, vault: vault)
            }
        }
    }
    
    func onVerify(_ tx: SendTransaction) {
        sendTx = tx
        navigateToVerify = true
    }
}

#Preview {
    FunctionTransactionScreen(
        vault: .example,
        transactionType: .bond(node: "test")
    )
}
