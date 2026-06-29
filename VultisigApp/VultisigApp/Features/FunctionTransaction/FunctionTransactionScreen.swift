//
//  FunctionTransactionScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-transaction-screen")

struct FunctionTransactionScreen: View {
    @Environment(\.router) var router
    let vault: Vault
    let transactionType: FunctionTransactionType

    @State private var isLoading: Bool = false

    private let blockchainService = BlockChainService.shared

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
            case .cosmosUndelegate(let coin, let valAddr, let valMoniker, let staked):
                resolvingCoin(coinMeta: coin) { coin in
                    CosmosUndelegateTransactionScreen(
                        viewModel: CosmosUndelegateTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            validatorAddress: valAddr,
                            validatorMoniker: valMoniker,
                            stakedBalance: staked
                        ),
                        onVerify: onVerify
                    )
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
                    SolanaDelegateTransactionScreen(
                        viewModel: SolanaDelegateTransactionViewModel(coin: coin, vault: vault),
                        onVerify: onVerify
                    )
                }
            case .solanaUnstake(let coin, let stakeAccount):
                resolvingCoin(coinMeta: coin) { coin in
                    SolanaUnstakeTransactionScreen(
                        viewModel: SolanaUnstakeTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            stakeAccount: stakeAccount
                        ),
                        onVerify: onVerify
                    )
                }
            case .solanaWithdraw(let coin, let stakeAccount):
                resolvingCoin(coinMeta: coin) { coin in
                    SolanaWithdrawTransactionScreen(
                        viewModel: SolanaWithdrawTransactionViewModel(
                            coin: coin,
                            vault: vault,
                            stakeAccount: stakeAccount
                        ),
                        onVerify: onVerify
                    )
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
                    immutableTx = immutableTx.copy(gas: scaledGas)
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

            var sendTx = transactionBuilder.buildSendTransaction(vault: vault)
            do {
                let chainSpecific = try await blockchainService.fetchSpecific(tx: sendTx)
                sendTx = sendTx.copy(gas: chainSpecific.gas)
            } catch {
                // Non-fatal: gas will be re-fetched during Verify. Keep
                // navigating so the user sees the verify screen even when
                // the upstream chain-specific endpoint is briefly down.
            }
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
