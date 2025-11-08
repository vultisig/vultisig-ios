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
                resolvingCoin(coin: vault.runeCoin) {
                    BondTransactionScreen(
                        viewModel: BondTransactionViewModel(
                            coin: $0,
                            vault: vault,
                            initialBondAddress: node
                        ),
                        onVerify: onVerify
                    )
                }
            case .unbond(let node):
                resolvingCoin(coin: vault.runeCoin) {
                    UnbondTransactionScreen(
                        viewModel: UnbondTransactionViewModel(
                            coin: $0,
                            vault: vault,
                            bondAddress: node.address
                        ),
                        onVerify: onVerify
                    )
                }
            case .stake(let coin):
                resolvingCoin(coinMeta: coin) {
                    StakeTransactionScreen(
                        viewModel: StakeTransactionViewModel(coin: $0, vault: vault),
                        onVerify: onVerify
                    )
                }
            case .unstake(let coin):
                resolvingCoin(coinMeta: coin) {
                    UnstakeTransactionScreen(
                        viewModel: UnstakeTransactionViewModel(coin: $0, vault: vault),
                        onVerify: onVerify
                    )
                }
            case .withdrawRewards(let coin, let rewards, let rewardsCoin):
                resolvingCoin(coinMeta: coin) {
                    WithdrawRewardsTransactionScreen(
                        viewModel: WithdrawRewardsTransactionViewModel(
                            coin: $0,
                            vault: vault,
                            rewards: rewards,
                            rewardsCoin: rewardsCoin
                        ),
                        onVerify: onVerify
                    )
                }
            case .mint(let coin, let yCoin):
                resolvingCoin(coinMeta: coin) { coin in
                    MintTransactionScreen(
                        viewModel: MintTransactionViewModel(coin: coin, yCoin: yCoin, vault: vault),
                        onVerify: onVerify
                    )
                }
            case .redeem(let coin, let yCoin):
                resolvingCoin(coinMeta: yCoin) { yCoin in
                    RedeemTransactionScreen(
                        viewModel: RedeemTransactionViewModel(
                            yCoin: yCoin,
                            coin: coin,
                            vault: vault
                        ),
                        onVerify: onVerify
                    )
                }
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
    
    @ViewBuilder
    func resolvingCoin<Content: View>(coinMeta: CoinMeta, content: (Coin) -> Content) -> some View {
        let coin = vault.coins.first(where: { $0.toCoinMeta() == coinMeta })
        resolvingCoin(coin: coin, content: content)
    }
    
    @ViewBuilder
    func resolvingCoin<Content: View>(coin: Coin?, content: (Coin) -> Content) -> some View {
        if let coin {
            content(coin)
        } else {
            // TODO: - Show error state
            EmptyView()
        }
    }
}

#Preview {
    FunctionTransactionScreen(
        vault: .example,
        transactionType: .bond(node: "test")
    )
}
