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
    @StateObject private var solanaStakeViewModel: SolanaStakeDefiViewModel
    @StateObject private var governanceViewModel: QBTCGovernanceViewModel
    @StateObject private var screenModel: DefiChainScreenModel
    @State private var showPositionSelection = false
    @State private var isLoading = false
    @State private var error: HelperError?
    @State private var refreshErrorToast: String?
    @State private var isRefreshing = false
    /// First `.onAppear` is covered by `.onLoad`; subsequent appearances mean the
    /// user returned from a pushed flow (e.g. a signed keysign), which is when the
    /// Solana stake reads must be invalidated and re-fetched.
    @State private var hasAppeared = false

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
        self._bondViewModel = StateObject(wrappedValue: DefiChainBondViewModel(vault: vault, chain: chain))
        self._lpsViewModel = StateObject(wrappedValue: DefiChainLPsViewModel(vault: vault, chain: chain))
        self._viewModel = StateObject(wrappedValue: DefiChainMainViewModel(vault: vault, chain: chain))
        self._stakeViewModel = StateObject(wrappedValue: DefiChainStakeViewModel(vault: vault, chain: chain))
        self._cosmosStakeViewModel = StateObject(wrappedValue: CosmosStakeDefiViewModel(chain: chain))
        self._solanaStakeViewModel = StateObject(wrappedValue: SolanaStakeDefiViewModel(vault: vault))
        self._governanceViewModel = StateObject(wrappedValue: QBTCGovernanceViewModel())
        self._screenModel = StateObject(wrappedValue: DefiChainScreenModel(vault: vault, chain: chain))
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
            // Warm the shared validator-set + metadata caches on tab load so the
            // validator picker opens without a cold re-download (the caches now
            // survive across opens via the shared service/provider).
            if chain.isSolanaStakingChain {
                solanaStakeViewModel.warmValidatorMetadata()
            }
            Task { await refresh() }
        }
        .onAppear {
            // Skip the load-time appearance; only re-invalidate on a true return.
            guard hasAppeared else {
                hasAppeared = true
                return
            }
            Task { await invalidateSolanaStakeIfNeeded() }
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
            CircularAccessoryIconButton(icon: .housePen, type: .secondary) {
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
                if chain.isSolanaStakingChain, let nativeCoin {
                    solanaStakeView(coin: nativeCoin)
                } else if chain.isCosmosStakingChain, let nativeCoin {
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
                    },
                    canVote: screenModel.canCoverVoteFee(nativeCoin: nativeCoin)
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

    /// Solana native-staking stake-segment renderer. Per-stake-account rows;
    /// the user-facing actions route through the shared
    /// `FunctionTransactionType.solana*` cases — the function-call router takes
    /// it from there. No claim action: Solana rewards auto-compound. Gated on
    /// the per-vault position opt-in exactly like the Cosmos stake segment.
    private func solanaStakeView(coin: Coin) -> some View {
        let fiatAmount = RateProvider.shared.fiatBalance(value: solanaStakeViewModel.totalStaked, coin: coin)
        let isPositionEnabled = vault.defiPositions
            .first(where: { $0.chain == chain })?
            .staking
            .contains(where: { $0.ticker == coin.ticker }) ?? false
        return SolanaStakeDefiView(
            coin: coin,
            totalFiat: fiatAmount.formatToFiat(includeCurrencySymbol: true),
            isPositionEnabled: isPositionEnabled,
            viewModel: solanaStakeViewModel,
            onDelegate: { coin in
                onTransactionToPresent(.solanaDelegate(coin: coin.toCoinMeta()))
            },
            onUnstake: { row in
                // Persist-light: only a live stake account (from the completed
                // refresh) may feed signing — a seed projection never does. The
                // row already gates Unstake on an active/activating delegation
                // and the deactivate flow has no editable field, so skip the
                // redundant confirm screen and go straight to Verify.
                guard let stakeAccount = row.stakeAccount, row.canUnstake else { return }
                presentVerify(for: SolanaUnstakeTransactionBuilder(
                    coin: coin,
                    stakeAccount: stakeAccount.pubkey
                ))
            },
            onWithdraw: { row in
                // The row gates Withdraw on a fully-inactive (cooled-down)
                // account — `canWithdraw` IS the cooldown guard, so a still-
                // cooling account never reaches here. A full withdraw has no
                // editable field, so skip the confirm screen: build from the
                // live account's whole balance and go straight to Verify.
                guard let stakeAccount = row.stakeAccount, row.canWithdraw else { return }
                let divisor = pow(Decimal(10), coin.decimals)
                let withdrawableAmount = Decimal(stakeAccount.lamports) / divisor
                presentVerify(for: SolanaWithdrawTransactionBuilder(
                    coin: coin,
                    stakeAccount: stakeAccount.pubkey,
                    amount: withdrawableAmount.formatToDecimal(digits: coin.decimals)
                ))
            },
            emptyStateView: { emptyStateView }
        )
    }

    func onStake(position: StakePosition) {
        onTransactionToPresent(screenModel.stakeTransactionType(for: position))
    }

    func onUnstake(position: StakePosition) {
        guard let type = screenModel.unstakeTransactionType(for: position) else { return }
        onTransactionToPresent(type)
    }

    func onTransfer(position: StakePosition) {
        guard let coin = screenModel.transferCoin(for: position) else { return }
        router.navigate(to: HomeRoute.vaultAction(
            action: .send(coin: coin, hasPreselectedCoin: true),
            vault: vault
        ))
    }

    func onGovernanceVote(proposal: CosmosGovProposal, choice: CosmosGovVoteChoice) {
        guard let tx = screenModel.makeGovernanceVoteTransaction(proposal: proposal, choice: choice) else { return }
        router.navigate(to: FunctionCallRoute.verify(tx: tx, vault: vault))
    }

    func onGovernanceWeightedVote(proposal: CosmosGovProposal, options: [CosmosGovVoteOption]) {
        guard let tx = screenModel.makeGovernanceWeightedVoteTransaction(proposal: proposal, options: options) else {
            return
        }
        router.navigate(to: FunctionCallRoute.verify(tx: tx, vault: vault))
    }

    func onTransactionToPresent(_ type: FunctionTransactionType) {
        Task { @MainActor in
            if screenModel.needsCoinAddition(for: type) {
                isLoading = true
                do {
                    try await screenModel.addCoins(for: type)
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

    /// Builds the unsigned tx and pushes straight to Verify — used by the Solana
    /// unstake/withdraw rows, which have no editable field and are already gated
    /// upstream (active/activating for unstake, fully inactive for withdraw), so
    /// the intermediate confirm screen would be redundant. The chain-specific
    /// gas is pre-fetched inside the model so Verify shows the fee immediately.
    func presentVerify(for builder: TransactionBuilder) {
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            let sendTx = await screenModel.buildVerifyTransaction(for: builder)
            router.navigate(to: FunctionCallRoute.verify(tx: sendTx, vault: vault))
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
        async let solanaRefresh: Void = refreshSolanaStakeIfNeeded()
        async let governanceRefresh: Void = refreshGovernanceIfNeeded()
        _ = await (mainRefresh, bondRefresh, stakeRefresh, lpsRefresh, cosmosRefresh, solanaRefresh, governanceRefresh)
    }

    /// Conditional refresh for the cosmos staking VM — only fires when the
    /// chain supports cosmos staking and the vault has the native coin
    /// loaded. Quiet no-op otherwise so non-Terra chains don't pay the cost.
    func refreshCosmosStakeIfNeeded() async {
        guard CosmosStakingConfig.isStakingSupported(chain) else { return }
        guard let nativeCoin else { return }
        await cosmosStakeViewModel.refresh(address: nativeCoin.address, decimals: nativeCoin.decimals)
    }

    /// Conditional refresh for the Solana staking VM — only fires on Solana and
    /// when the vault has the native coin loaded. Quiet no-op otherwise so other
    /// chains don't pay the cost. Stake accounts are read uncached, so this
    /// always reflects a just-submitted delegate/unstake/withdraw/move.
    func refreshSolanaStakeIfNeeded() async {
        guard chain.isSolanaStakingChain, let nativeCoin else { return }
        await solanaStakeViewModel.refresh(owner: nativeCoin.address, decimals: nativeCoin.decimals)
    }

    /// Cache-invalidating Solana stake refresh — runs when the user returns to
    /// the DeFi screen after a pushed flow (e.g. a signed delegate / unstake /
    /// withdraw / move keysign). Clears the short-lived epoch cache and also
    /// re-reads the native-coin staked balance so the aggregate DeFi balance and
    /// the per-account rows both reflect the just-submitted tx.
    func invalidateSolanaStakeIfNeeded() async {
        guard chain.isSolanaStakingChain, let nativeCoin else { return }
        async let rows: Void = solanaStakeViewModel.invalidateAndRefresh(
            owner: nativeCoin.address,
            decimals: nativeCoin.decimals
        )
        async let balance: Void = BalanceService.shared.updateBalance(for: nativeCoin)
        _ = await (rows, balance)
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
        screenModel.update(vault: vault)
    }
}

#Preview {
    DefiChainMainScreen(vault: .example, chain: .thorChain)
        .environmentObject(HomeViewModel())
}
