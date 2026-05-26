//
//  FunctionTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

struct FunctionTransactionScreen: View {
    @Environment(\.router) var router
    let vault: Vault
    let transactionType: FunctionTransactionType

    @StateObject private var functionCallViewModel = FunctionCallViewModel()
    @State private var sendTx: FunctionCallForm?
    @State var isLoading: Bool = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            switch transactionType {
            case .bond(let coin, let node):
                resolvingCoin(coinMeta: coin) { coin in
                    switch coin.chain {
                    case .mayaChain:
                        BondMayaTransactionScreen(
                            viewModel: BondMayaTransactionViewModel(
                                coin: coin,
                                vault: vault,
                                initialBondAddress: node
                            ),
                            onVerify: onVerify
                        )
                    default:
                        BondTransactionScreen(
                            viewModel: BondTransactionViewModel(
                                coin: coin,
                                vault: vault,
                                initialBondAddress: node
                            ),
                            onVerify: onVerify
                        )
                    }
                }
            case .unbond(let node):
                resolvingCoin(coinMeta: node.coin) { coin in
                    switch coin.chain {
                    case .mayaChain:
                        UnbondMayaTransactionScreen(
                            viewModel: UnbondMayaTransactionViewModel(
                                coin: coin,
                                vault: vault,
                                initialBondAddress: node.address
                            ),
                            onVerify: onVerify
                        )
                    default:
                        UnbondTransactionScreen(
                            viewModel: UnbondTransactionViewModel(
                                coin: coin,
                                vault: vault,
                                bondAddress: node.address
                            ),
                            onVerify: onVerify
                        )
                    }
                }
            case .stake(let coin, let isAutocompound):
                resolvingCoin(coinMeta: coin) {
                    StakeTransactionScreen(
                        viewModel: StakeTransactionViewModel(coin: $0, vault: vault, isAutocompound: isAutocompound),
                        onVerify: onVerify
                    )
                }
            case .unstake(let coin, let isAutocompound, let availableToUnstake):
                resolvingCoin(coinMeta: coin) {
                    UnstakeTransactionScreen(
                        viewModel: UnstakeTransactionViewModel(
                            coin: $0,
                            vault: vault,
                            isAutocompound: isAutocompound,
                            availableToUnstake: availableToUnstake
                        ),
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
            case .addLP(let position):
                resolvingCoins(coin: position.coin1, coin2: position.coin2) { coin1, coin2 in
                    AddLPTransactionScreen(
                        viewModel: AddLPTransactionViewModel(
                            coin: coin1,
                            coin2: coin2,
                            vault: vault,
                            position: position
                        ),
                        onVerify: onVerify
                    )
                }
            case .removeLP(let position):
                resolvingCoin(coinMeta: position.coin1) { coin1 in
                    RemoveLPTransactionScreen(
                        viewModel: RemoveLPTransactionViewModel(
                            coin: coin1,
                            vault: vault,
                            position: position
                        ),
                        onVerify: onVerify
                    )
                }
            case .cosmosDelegate(let coin):
                resolvingCoin(coinMeta: coin) { coin in
                    CosmosDelegateTransactionScreen(
                        viewModel: CosmosDelegateTransactionViewModel(coin: coin, vault: vault),
                        onVerify: onVerify
                    )
                }
            }
        }
        .withLoading(isLoading: $isLoading)
    }

    func onVerify(_ transactionBuilder: TransactionBuilder) {
        Task { @MainActor in
            // Cosmos staking flows bypass the legacy `FunctionCallForm`
            // round-trip — the SignDoc payload travels via
            // `SendTransaction.cosmosStakingPayload`, which `fromForm(_:)`
            // would drop. Skip directly to the immutable struct so the
            // Verify → KeysignPayload resolver sees the staking intent.
            if transactionBuilder.cosmosStakingPayload != nil {
                isLoading = true
                let immutableTx = transactionBuilder.buildSendTransaction(vault: vault)
                isLoading = false
                router.navigate(to: FunctionCallRoute.verify(tx: immutableTx, vault: vault))
                return
            }

            isLoading = true
            let tx = transactionBuilder.buildTransaction()

            await functionCallViewModel.loadGasInfoForSending(tx: tx)

            sendTx = tx
            isLoading = false
            let immutableTx = SendTransaction.fromForm(tx, vault: vault)
            router.navigate(to: FunctionCallRoute.verify(tx: immutableTx, vault: vault))
        }
    }

    @ViewBuilder
    func resolvingCoin<Content: View>(coinMeta: CoinMeta, @ViewBuilder content: (Coin) -> Content) -> some View {
        let coin = vault.coins.first(where: { $0.toCoinMeta() == coinMeta })
        resolvingCoin(coin: coin, content: content)
    }

    @ViewBuilder
    func resolvingCoin<Content: View>(coin: Coin?, content: (Coin) -> Content) -> some View {
        if let coin {
            content(coin)
        } else {
            ErrorView(
                type: .alert,
                title: "functionTransactionScreenErrorTitle".localized,
                description: "functionTransactionScreenErrorSubtitle".localized,
                buttonTitle: "tryAgain".localized
            ) {
                dismiss()
            }
        }
    }

    @ViewBuilder
    func resolvingCoins<Content: View>(coin: CoinMeta, coin2: CoinMeta, content: (Coin, Coin) -> Content) -> some View {
        resolvingCoin(coinMeta: coin) { coin1 in
            resolvingCoin(coinMeta: coin2) { resolvedCoin2 in
                content(coin1, resolvedCoin2)
            }
        }
    }
}

#Preview {
    FunctionTransactionScreen(
        vault: .example,
        transactionType: .bond(coin: .example, node: "test")
    )
}
