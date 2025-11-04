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
    
    @StateObject private var functionCallViewModel = FunctionCallViewModel()
    @State private var sendTx: SendTransaction?
    @State private var navigateToVerify: Bool = false
    @State var isLoading: Bool = false
    
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
        .withLoading(isLoading: $isLoading)
        .navigationDestination(isPresented: $navigateToVerify) {
            if let sendTx {
                FunctionCallRouteBuilder().buildVerifyScreen(tx: sendTx, vault: vault)
            }
        }
    }
    
    func onVerify(_ transactionBuilder: TransactionBuilder) {
        Task { @MainActor in
            isLoading = true
            let tx = transactionBuilder.buildTransaction()
            
            await functionCallViewModel.loadGasInfoForSending(tx: tx)
            await functionCallViewModel.loadFastVault(tx: tx, vault: vault)
            
            sendTx = tx
            isLoading = false
            navigateToVerify = true
        }
    }
}

#Preview {
    FunctionTransactionScreen(
        vault: .example,
        transactionType: .bond(node: "test")
    )
}
