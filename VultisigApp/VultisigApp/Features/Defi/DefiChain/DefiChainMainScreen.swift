//
//  DefiChainMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiChainMainScreen: View {
    @Environment(\.router) var router
    @ObservedObject var vault: Vault
    let chain: Chain

    @StateObject private var viewModel: DefiChainMainViewModel
    @StateObject private var bondViewModel: DefiChainBondViewModel
    @StateObject private var lpsViewModel: DefiChainLPsViewModel
    @StateObject private var stakeViewModel: DefiChainStakeViewModel
    @StateObject private var cosmosStakeViewModel: CosmosStakeDefiViewModel
    @StateObject private var governanceViewModel: QBTCGovernanceViewModel
    @State private var showPositionSelection = false
    @State private var isLoading = false
    @State private var error: HelperError?
    @State private var refreshErrorToast: String?
    @State private var isRefreshing = false

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
        self._bondViewModel = StateObject(wrappedValue: DefiChainBondViewModel(vault: vault, chain: chain))
        self._lpsViewModel = StateObject(wrappedValue: DefiChainLPsViewModel(vault: vault, chain: chain))
        self._viewModel = StateObject(wrappedValue: DefiChainMainViewModel(vault: vault, chain: chain))
        self._stakeViewModel = StateObject(wrappedValue: DefiChainStakeViewModel(vault: vault, chain: chain))
        self._cosmosStakeViewModel = StateObject(wrappedValue: CosmosStakeDefiViewModel(chain: chain))
        self._governanceViewModel = StateObject(wrappedValue: QBTCGovernanceViewModel())
    }

    private var nativeCoin: Coin? {
        vault.nativeCoin(for: chain)
    }

    /// Surfaced via the `.withBanner(...)` toast modifier. Only Bond surfaces a refresh error
    /// today — Stake and LP refreshes silently keep persisted rows on failure (see ViewModels).
    private var refreshError: String? {
        bondViewModel.refreshError
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                DefiChainBalanceView(vault: vault, chain: chain)
                positionsSegmentedControlView
                selectedPositionView
            }
            .padding(.top, isMacOS ? 60 : 16)
            .padding(.horizontal, 16)
        }
        .background(MainBackgroundWithNotification())
        .overlay(bottomGradient, alignment: .bottom)
        .onLoad {
            viewModel.onLoad()
            Task { await refresh() }
        }
        .refreshable {
            // SwiftUI binds the `.refreshable` task to the refresh-control's spinner.
            // When the user lets go, the spinner dismisses and the task is cancelled —
            // which propagates to every in-flight network call inside `refresh()` and
            // surfaces as `CancellationError`. Detach so cancellation stops here.
            await Task { @MainActor in await refresh() }.value
        }
        .onChange(of: vault) { _, vault in
            update(vault: vault)
        }
        .onChange(of: vault.defiPositions) { _, _ in
            Task { await refresh() }
        }
        // Segment switching does NOT refresh — `refresh()` already loads all three position
        // types in parallel on initial load and pull-to-refresh, so the data the new segment
        // needs is already cached. Re-running `refresh()` here would fire 4 extra API calls
        // every time the user swipes between segments.
        .onChange(of: refreshError) { _, newValue in
            refreshErrorToast = newValue
        }
        .crossPlatformSheet(isPresented: $showPositionSelection) {
            DefiChainSelectPositionsScreen(
                viewModel: viewModel,
                isPresented: $showPositionSelection
            )
        }
        .crossPlatformToolbar(ignoresTopEdge: true) {
            #if os(macOS)
            CustomToolbarItem(placement: .trailing) {
                RefreshToolbarButton(onRefresh: { Task { await refresh() } })
            }
            #endif
        }
        .withLoading(isLoading: $isLoading)
        .withBanner(text: $refreshErrorToast, style: .error)
        .alert(item: $error) { error in
            Alert(
                title: Text(NSLocalizedString("error", comment: "")),
                message: Text(NSLocalizedString(error.localizedDescription, comment: "")),
                dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
            )
        }
    }

    var positionsSegmentedControlView: some View {
        HStack(spacing: .zero) {
            SegmentedControl(selection: $viewModel.selectedPosition, items: viewModel.positions)
                .fixedSize()
            Spacer()
            CircularAccessoryIconButton(icon: "crypto-wallet-pen", type: .secondary) {
                showPositionSelection.toggle()
            }
        }
    }

    var selectedPositionView: some View {
        Group {
            switch viewModel.selectedPosition {
            case .bond:
                if let nativeCoin {
                    DefiChainBondedView(
                        viewModel: bondViewModel,
                        coin: nativeCoin,
                        onBond: { onTransactionToPresent(.bond(coin: nativeCoin.toCoinMeta(), node: $0?.address)) },
                        onUnbond: { onTransactionToPresent(.unbond(node: $0)) },
                        emptyStateView: { emptyStateView }
                    )
                }
            case .stake:
                if chain.isCosmosStakingChain, let nativeCoin {
                    cosmosStakeView(coin: nativeCoin)
                } else {
                    DefiChainStakedView(
                        viewModel: stakeViewModel,
                        onStake: { onStake(position: $0) },
                        onUnstake: { onUnstake(position: $0) },
                        onWithdraw: { position in
                            guard let rewards = position.rewards, let rewardsCoin = position.rewardCoin else {
                                return
                            }
                            onTransactionToPresent(.withdrawRewards(
                                coin: position.coin,
                                rewards: rewards,
                                rewardsCoin: rewardsCoin
                            ))
                        },
                        onTransfer: { onTransfer(position: $0) },
                        emptyStateView: { emptyStateView }
                    )
                }
            case .liquidityPool:
                DefiChainLPsView(
                    vault: vault,
                    viewModel: lpsViewModel,
                    onRemove: {
                        onTransactionToPresent(.removeLP(position: $0))
                    },
                    onAdd: {
                        onTransactionToPresent(.addLP(position: $0))
                    },
                    emptyStateView: { emptyStateView }
                )
            case .governance:
                QBTCGovernanceView(
                    viewModel: governanceViewModel,
                    onVote: { proposal, choice in
                        onGovernanceVote(proposal: proposal, choice: choice)
                    },
                    onWeightedVote: { proposal, options in
                        onGovernanceWeightedVote(proposal: proposal, options: options)
                    }
                )
            }
        }
        .transition(.opacity)
        .animation(.easeInOut, value: viewModel.selectedPosition)
        .gesture(dragGesture)
    }

    var emptyStateView: some View {
        ActionBannerView(
            title: "noPositionsSelectedTitle".localized,
            subtitle: "noPositionsSelectedSubtitle".localized,
            buttonTitle: "managePositions".localized,
            action: { showPositionSelection.toggle() }
        )
    }

    /// LUNA / LUNC stake-segment renderer. Routes the four user-facing
    /// actions through the shared `FunctionTransactionType.cosmos*`
    /// cases — the function-call router takes it from there.
    private func cosmosStakeView(coin: Coin) -> some View {
        let fiatAmount = RateProvider.shared.fiatBalance(value: cosmosStakeViewModel.totalStaked, coin: coin)
        let isPositionEnabled = vault.defiPositions
            .first(where: { $0.chain == chain })?
            .staking
            .contains(where: { $0.ticker == coin.ticker }) ?? false
        return CosmosStakeDefiView(
            coin: coin,
            totalFiat: fiatAmount.formatToFiat(includeCurrencySymbol: true),
            isPositionEnabled: isPositionEnabled,
            viewModel: cosmosStakeViewModel,
            onDelegate: { coin in
                onTransactionToPresent(.cosmosDelegate(coin: coin.toCoinMeta()))
            },
            onUndelegate: { position in
                onTransactionToPresent(.cosmosUndelegate(
                    coin: coin.toCoinMeta(),
                    validatorAddress: position.validatorAddress,
                    validatorMoniker: position.validatorMoniker,
                    stakedAmount: position.stakedAmount
                ))
            },
            onRedelegate: { position in
                onTransactionToPresent(.cosmosRedelegate(
                    coin: coin.toCoinMeta(),
                    validatorAddress: position.validatorAddress,
                    validatorMoniker: position.validatorMoniker,
                    stakedAmount: position.stakedAmount
                ))
            },
            onClaim: { rows in
                let candidates = rows.map {
                    CosmosWithdrawRewardsCandidate(
                        validatorAddress: $0.validatorAddress,
                        validatorMoniker: $0.validatorMoniker,
                        pendingReward: $0.pendingReward
                    )
                }
                onTransactionToPresent(.cosmosWithdrawRewards(
                    coin: coin.toCoinMeta(),
                    validators: candidates
                ))
            },
            emptyStateView: { emptyStateView }
        )
    }

    func onStake(position: StakePosition) {
        switch position.type {
        case .stake:
            onTransactionToPresent(.stake(coin: position.coin, isAutocompound: false))
        case .compound:
            onTransactionToPresent(.stake(coin: stakeCoin(for: position.coin), isAutocompound: true))
        case .index:
            onTransactionToPresent(.mint(coin: coin(for: position.coin), yCoin: position.coin))
        }
    }

    func onUnstake(position: StakePosition) {
        switch position.type {
        case .stake:
            onTransactionToPresent(
                .unstake(
                    coin: position.coin,
                    isAutocompound: false,
                    availableToUnstake: position.availableToUnstake
                )
            )
        case .compound:
            onTransactionToPresent(
                .unstake(
                    coin: stakeCoin(for: position.coin),
                    isAutocompound: true,
                    availableToUnstake: position.amount
                )
            )
        case .index:
            onTransactionToPresent(.redeem(coin: coin(for: position.coin), yCoin: position.coin))
        }
    }

    func onTransfer(position: StakePosition) {
        guard let coin = vault.coins.first(where: { $0.toCoinMeta() == position.coin }) else {
            return
        }
        router.navigate(to: HomeRoute.vaultAction(
            action: .send(coin: coin, hasPreselectedCoin: true),
            vault: vault
        ))
    }

    func stakeCoin(for compoundCoin: CoinMeta) -> CoinMeta {
        switch compoundCoin.ticker.uppercased() {
        case "STCY":
            return TokensStore.tcy
        default:
            return compoundCoin
        }
    }

    func coin(for yCoin: CoinMeta) -> CoinMeta {
        let coin: CoinMeta
        switch yCoin {
        case TokensStore.yrune:
            coin = TokensStore.rune
        case TokensStore.ytcy:
            coin = TokensStore.tcy
        default:
            coin = TokensStore.rune
        }
        return coin
    }

    /// Builds a single-option QBTC governance vote tx straight from the
    /// proposal + chosen option and pushes it to the existing verify → ML-DSA
    /// keysign flow. The memo (`QBTC_VOTE:<OPTION>:<ID>`) is what
    /// `QBTCHelper.buildMsgVote` consumes; the dictionary is display-only so
    /// verify reads "Vote <OPTION> on Proposal #N" rather than the raw memo.
    func onGovernanceVote(proposal: CosmosGovProposal, choice: CosmosGovVoteChoice) {
        guard let nativeCoin else { return }
        let memo = "QBTC_VOTE:\(choice.memoToken):\(proposal.id)"
        let displayDictionary: [String: String] = [
            "action": "governanceVoteAction".localized,
            "vote": choice.displayTitle,
            "proposal": String(format: "governanceProposalNumber".localized, String(proposal.id))
        ]
        let tx = SendTransaction.empty(coin: nativeCoin, vault: vault).copy(
            memo: memo,
            transactionType: .vote,
            memoFunctionDictionary: displayDictionary
        )
        router.navigate(to: FunctionCallRoute.verify(tx: tx, vault: vault))
    }

    /// Builds a weighted QBTC governance vote tx from per-option weights and
    /// pushes it to verify → ML-DSA keysign. The memo
    /// (`QBTC_VOTEW:<ID>:OPT=W,...`) is what `QBTCHelper.buildMsgVoteWeighted`
    /// consumes; weights are passed as plain decimals and the helper
    /// canonicalizes them to the 18-decimal `cosmos.Dec` form.
    func onGovernanceWeightedVote(proposal: CosmosGovProposal, options: [CosmosGovVoteOption]) {
        guard let nativeCoin, !options.isEmpty else { return }
        let optionsPart = options
            .map { "\($0.option.memoToken)=\(Self.weightString($0.weight))" }
            .joined(separator: ",")
        let memo = "QBTC_VOTEW:\(proposal.id):\(optionsPart)"
        let displayValue = options
            .map { "\($0.option.displayTitle) \(Self.weightPercentString($0.weight))" }
            .joined(separator: ", ")
        let displayDictionary: [String: String] = [
            "action": "governanceVoteAction".localized,
            "vote": displayValue,
            "proposal": String(format: "governanceProposalNumber".localized, String(proposal.id))
        ]
        let tx = SendTransaction.empty(coin: nativeCoin, vault: vault).copy(
            memo: memo,
            transactionType: .vote,
            memoFunctionDictionary: displayDictionary
        )
        router.navigate(to: FunctionCallRoute.verify(tx: tx, vault: vault))
    }

    /// Plain decimal string for a weight fraction (e.g. 0.7 -> "0.7"), fed to
    /// the memo. `QBTCHelper` re-pads it to the canonical `cosmos.Dec` form.
    static func weightString(_ weight: Decimal) -> String {
        NSDecimalNumber(decimal: weight).stringValue
    }

    /// Percentage label for the verify summary (e.g. 0.7 -> "70%").
    static func weightPercentString(_ weight: Decimal) -> String {
        let percent = NSDecimalNumber(decimal: weight * 100).intValue
        return "\(percent)%"
    }

    func onTransactionToPresent(_ type: FunctionTransactionType) {
        Task { @MainActor in
            let vaultCoins = vault.coins.map { $0.toCoinMeta() }
            let shouldAdd = type.coins.contains { !vaultCoins.contains($0) }

            if shouldAdd {
                isLoading = true
                do {
                    try await CoinService.addToChain(assets: type.coins, to: vault)
                } catch {
                    self.error = HelperError.runtimeError("Failed to add coins")
                    isLoading = false
                    return
                }
                isLoading = false
            }

            router.navigate(to: FunctionCallRoute.functionTransaction(
                vault: vault,
                transactionType: type
            ))
        }
    }
}

private extension DefiChainMainScreen {
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 50, coordinateSpace: .local)
            .onEnded { value in
                let horizontalMovement = value.translation.width
                let verticalMovement = value.translation.height

                // Only handle if it's a primarily horizontal swipe with significant distance
                if abs(horizontalMovement) > abs(verticalMovement) * 2 && abs(horizontalMovement) > 80 {
                    withAnimation(.easeInOut) {
                        if horizontalMovement > 0 {
                            // Swipe right - move to previous position
                            viewModel.moveToPreviousPosition()
                        } else {
                            // Swipe left - move to next position
                            viewModel.moveToNextPosition()
                        }
                    }
                }
            }
    }

    var bottomGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Theme.colors.bgPrimary, location: 0.3),
                Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0.5), location: 0.6),
                Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.5, y: 1),
            endPoint: UnitPoint(x: 0.5, y: 0)
        )
        .ignoresSafeArea()
        .frame(height: 30)
    }
}

private extension DefiChainMainScreen {
    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        // `defer` runs even on Task cancellation (e.g. view disappears
        // mid-refresh). Without it, the flag stays `true` forever and the
        // guard above silently drops every subsequent refresh call.
        defer { isRefreshing = false }

        // Refresh all three position categories in parallel so the aggregate balance shown
        // in `DefiChainBalanceView` reflects every position type — not just the currently
        // selected segment. The native-coin balance refresh runs independently.
        async let mainRefresh: Void = viewModel.refresh()
        async let bondRefresh: Void = bondViewModel.refresh()
        async let stakeRefresh: Void = stakeViewModel.refresh()
        async let lpsRefresh: Void = lpsViewModel.refresh()
        async let cosmosRefresh: Void = refreshCosmosStakeIfNeeded()
        async let governanceRefresh: Void = refreshGovernanceIfNeeded()
        _ = await (mainRefresh, bondRefresh, stakeRefresh, lpsRefresh, cosmosRefresh, governanceRefresh)
    }

    /// Conditional refresh for the cosmos staking VM — only fires when the
    /// chain supports cosmos staking and the vault has the native coin
    /// loaded. Quiet no-op otherwise so non-Terra chains don't pay the cost.
    func refreshCosmosStakeIfNeeded() async {
        guard CosmosStakingConfig.isStakingSupported(chain) else { return }
        guard let nativeCoin else { return }
        await cosmosStakeViewModel.refresh(address: nativeCoin.address, decimals: nativeCoin.decimals)
    }

    /// Conditional refresh for the QBTC governance VM — only fires on QBTC,
    /// the one chain with the governance segment. Quiet no-op elsewhere.
    func refreshGovernanceIfNeeded() async {
        guard chain == .qbtc else { return }
        await governanceViewModel.refresh(voterAddress: nativeCoin?.address)
    }

    func update(vault: Vault) {
        viewModel.update(vault: vault)
        bondViewModel.update(vault: vault)
        lpsViewModel.update(vault: vault)
        stakeViewModel.update(vault: vault)
    }
}

#Preview {
    DefiChainMainScreen(vault: .example, chain: .thorChain)
        .environmentObject(HomeViewModel())
}
