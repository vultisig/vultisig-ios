//
//  FunctionTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import OSLog
import SwiftUI

private let logger = Log.send.view

struct FunctionTransactionScreen: View {
    @Environment(\.router) var router
    let vault: Vault
    let transactionType: FunctionTransactionType

    @State private var isLoading: Bool = false

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
            case .unbond(let coinMeta, let node):
                resolvingCoin(coinMeta: coinMeta) { coin in
                    switch coin.chain {
                    case .mayaChain:
                        UnbondMayaTransactionScreen(
                            viewModel: UnbondMayaTransactionViewModel(
                                coin: coin,
                                vault: vault,
                                initialBondAddress: node?.address
                            ),
                            onVerify: onVerify
                        )
                    default:
                        UnbondTransactionScreen(
                            viewModel: UnbondTransactionViewModel(
                                coin: coin,
                                vault: vault,
                                bondAddress: node?.address ?? .empty
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
            case .addLP(let position, let side):
                resolvingCoins(coin: position.coin1, coin2: position.coin2) { coin1, coin2 in
                    AddLPTransactionScreen(
                        viewModel: AddLPTransactionViewModel.position(
                            coin1: coin1,
                            coin2: coin2,
                            side: side,
                            position: position,
                            vault: vault
                        ),
                        onVerify: onVerify
                    )
                }
            case .addThorchainLP(let coin):
                resolvingCoin(coinMeta: coin) { coin in
                    AddLPTransactionScreen(
                        viewModel: AddLPTransactionViewModel.chain(coin: coin, vault: vault),
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
                    StakingTransactionScreen(
                        viewModel: CosmosDelegateTransactionViewModel(coin: coin, vault: vault),
                        onVerify: onVerify
                    ) { isPresented, viewModel in
                        StakingValidatorPickerScreen(
                            isPresented: isPresented,
                            selectedValidator: Binding(
                                get: { viewModel.selectedValidator },
                                set: { viewModel.selectedValidator = $0 }
                            ),
                            source: .cosmos(chain: coin.chain),
                            chainTicker: coin.ticker,
                            chainDecimals: coin.decimals
                        )
                    }
                }
            case .cosmosUndelegate(let coin, let valAddr, let valMoniker, let staked):
                resolvingCoin(coinMeta: coin) { coin in
                    StakingTransactionScreen(
                        viewModel: CosmosUndelegateTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            validatorAddress: valAddr,
                            validatorMoniker: valMoniker,
                            stakedBalance: staked
                        ),
                        onVerify: onVerify
                    ) { _, _ in EmptyView() }
                }
            case .cosmosRedelegate(let coin, let valAddr, let valMoniker, let staked):
                resolvingCoin(coinMeta: coin) { coin in
                    CosmosRedelegateTransactionScreen(
                        viewModel: CosmosRedelegateTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            validatorSrcAddress: valAddr,
                            validatorSrcMoniker: valMoniker,
                            stakedBalance: staked
                        ),
                        onVerify: onVerify
                    )
                }
            case .cosmosWithdrawRewards(let coin, let validators):
                resolvingCoin(coinMeta: coin) { coin in
                    CosmosWithdrawRewardsTransactionScreen(
                        viewModel: CosmosWithdrawRewardsTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            candidates: validators
                        ),
                        onVerify: onVerify
                    )
                }
            case .solanaDelegate(let coin):
                resolvingCoin(coinMeta: coin) { coin in
                    StakingTransactionScreen(
                        viewModel: SolanaDelegateTransactionViewModel(coin: coin, vault: vault),
                        onVerify: onVerify
                    ) { isPresented, viewModel in
                        StakingValidatorPickerScreen(
                            isPresented: isPresented,
                            selectedValidator: Binding(
                                get: { viewModel.selectedValidator },
                                set: { viewModel.selectedValidator = $0 }
                            ),
                            source: .solana(),
                            chainTicker: coin.ticker,
                            chainDecimals: coin.decimals
                        )
                    }
                }
            case .tonStake(let coin, let poolAddress, let poolImplementation):
                resolvingCoin(coinMeta: coin) { coin in
                    TonStakeTransactionScreen(
                        viewModel: TonStakeTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            existingPoolAddress: poolAddress,
                            existingPoolImplementation: poolImplementation
                        ),
                        onVerify: onVerify
                    )
                }
            case .tonUnstake(let coin, let poolAddress, let poolImplementation, let stakedAmount):
                resolvingCoin(coinMeta: coin) { coin in
                    TonUnstakeTransactionScreen(
                        viewModel: TonUnstakeTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            poolAddress: poolAddress,
                            poolImplementation: poolImplementation,
                            stakedAmount: stakedAmount
                        ),
                        onVerify: onVerify
                    )
                }
            case .leave(let coin, let node):
                resolvingCoin(coinMeta: coin) { coin in
                    LeaveTransactionScreen(
                        viewModel: LeaveTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            initialNodeAddress: node
                        ),
                        onVerify: onVerify
                    )
                }
            case .rebond(let coin, let node):
                resolvingCoin(coinMeta: coin) { coin in
                    RebondTransactionScreen(
                        viewModel: RebondTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            initialNodeAddress: node
                        ),
                        onVerify: onVerify
                    )
                }
            case .merge(let coin, let denom):
                resolvingCoin(coinMeta: coin) { coin in
                    MergeTransactionScreen(
                        viewModel: MergeTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            initialDenom: denom
                        ),
                        onVerify: onVerify
                    )
                }
            case .unmerge(let coin, let denom):
                resolvingCoin(coinMeta: coin) { coin in
                    UnmergeTransactionScreen(
                        viewModel: UnmergeTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            initialDenom: denom
                        ),
                        onVerify: onVerify
                    )
                }
            case .withdrawSecuredAsset(let coin):
                resolvingCoin(coinMeta: coin) { coin in
                    SecuredWithdrawTransactionScreen(
                        viewModel: SecuredWithdrawTransactionViewModel(coin: coin, vault: vault),
                        onVerify: onVerify
                    )
                }
            case .theSwitch(let coin):
                resolvingCoin(coinMeta: coin) { coin in
                    SwitchTransactionScreen(
                        viewModel: SwitchTransactionViewModel(coin: coin, vault: vault),
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
            if let stakingPayload = transactionBuilder.cosmosStakingPayload {
                isLoading = true
                var immutableTx = transactionBuilder.buildSendTransaction(vault: vault)
                // `buildSendTransaction` defaults gas to .zero and the staking
                // flow never fetches chain-specific gas (the SignDoc resolver
                // bakes a fixed per-chain fee instead). Set gas to the SAME
                // value the resolver signs — `feeAmount × msgCount` from the
                // shared `CosmosStakingConfig` helper — so the verify screen's
                // fee row and balance preflight match what is actually signed
                // (delegate/undelegate/redelegate = 1 msg; a batched claim =
                // one msg per validator). Without this the user approves a fee
                // shown as 0 while signing 7500×N (and Terra shows 0 too).
                do {
                    let scaledGas = try CosmosStakingConfig.scaledFeeAmountBigInt(
                        for: transactionBuilder.coin.chain,
                        msgCount: stakingPayload.msgCount
                    )
                    // Both figures: `displayFee` reads `gas` on Cosmos, every
                    // fiat fee string reads `fee`, and for a Cosmos SignDoc the
                    // per-unit gas IS the whole cost — so they are the same
                    // number and disagreeing about it only prints `$0.00` under
                    // a real crypto amount.
                    immutableTx = immutableTx.copy(gas: scaledGas, fee: scaledGas)
                } catch {
                    // Unreachable for the staking-supported chains that ever
                    // populate `cosmosStakingPayload`; log rather than swallow
                    // so a future chain missing from the config table surfaces
                    // here instead of silently showing a 0 fee again.
                    logger.error(
                        "Failed to derive staking display fee: \(error.localizedDescription, privacy: .public)"
                    )
                }
                isLoading = false
                router.navigate(to: FunctionCallRoute.verify(tx: immutableTx, vault: vault))
                return
            }

            isLoading = true
            defer { isLoading = false }

            // Priced before it is disclosed. Nothing downstream re-resolves the
            // fee for display, so this figure is the one the user approves.
            let sendTx = await transactionBuilder.buildPricedSendTransaction(vault: vault)
            router.navigate(to: FunctionCallRoute.verify(tx: sendTx, vault: vault))
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
