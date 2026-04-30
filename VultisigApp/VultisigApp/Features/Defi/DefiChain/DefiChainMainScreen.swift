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

    @StateObject var viewModel: DefiChainMainViewModel
    @StateObject var bondViewModel: DefiChainBondViewModel
    @StateObject var lpsViewModel: DefiChainLPsViewModel
    @StateObject var stakeViewModel: DefiChainStakeViewModel
    @StateObject var sendTx = SendTransaction()
    @State private var showPositionSelection = false
    @State private var isLoading = false
    @State private var error: HelperError?
    @State private var refreshErrorToast: String?

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
        self._bondViewModel = StateObject(wrappedValue: DefiChainBondViewModel(vault: vault, chain: chain))
        self._lpsViewModel = StateObject(wrappedValue: DefiChainLPsViewModel(vault: vault, chain: chain))
        self._viewModel = StateObject(wrappedValue: DefiChainMainViewModel(vault: vault, chain: chain))
        self._stakeViewModel = StateObject(wrappedValue: DefiChainStakeViewModel(vault: vault, chain: chain))
    }

    private var nativeCoin: Coin? {
        vault.nativeCoin(for: chain)
    }

    /// Surfaced via the `.withBanner(...)` toast modifier; the active segment's VM owns the
    /// underlying error state.
    private var refreshError: String? {
        switch viewModel.selectedPosition {
        case .bond: return bondViewModel.refreshError
        case .stake: return stakeViewModel.refreshError
        case .liquidityPool: return lpsViewModel.refreshError
        }
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
        .refreshable { await refresh() }
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
        .crossPlatformToolbar(ignoresTopEdge: true) {}
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
        sendTx.reset(coin: coin)
        router.navigate(to: HomeRoute.vaultAction(
            action: .send(coin: coin, hasPreselectedCoin: true),
            sendTx: sendTx,
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
        // Refresh all three position categories in parallel so the aggregate balance shown
        // in `DefiChainBalanceView` reflects every position type — not just the currently
        // selected segment. The native-coin balance refresh runs independently.
        async let mainRefresh: Void = viewModel.refresh()
        async let bondRefresh: Void = bondViewModel.refresh()
        async let stakeRefresh: Void = stakeViewModel.refresh()
        async let lpsRefresh: Void = lpsViewModel.refresh()
        _ = await (mainRefresh, bondRefresh, stakeRefresh, lpsRefresh)
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
