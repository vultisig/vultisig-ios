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
    let group: GroupedChain

    @StateObject var viewModel: DefiChainMainViewModel
    @StateObject var bondViewModel: DefiChainBondViewModel
    @StateObject var lpsViewModel: DefiChainLPsViewModel
    @StateObject var stakeViewModel: DefiChainStakeViewModel
    @State private var showPositionSelection = false
    @State private var isLoading = false
    @State private var error: HelperError?
    
    init(vault: Vault, group: GroupedChain) {
        self.vault = vault
        self.group = group
        self._bondViewModel = StateObject(wrappedValue: DefiChainBondViewModel(vault: vault, chain: group.chain))
        self._lpsViewModel = StateObject(wrappedValue: DefiChainLPsViewModel(vault: vault, chain: group.chain))
        self._viewModel = StateObject(wrappedValue: DefiChainMainViewModel(vault: vault, chain: group.chain))
        self._stakeViewModel = StateObject(wrappedValue: DefiChainStakeViewModel(vault: vault, chain: group.chain))
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                DefiChainBalanceView(vault: vault, groupedChain: group)
                positionsSegmentedControlView
                selectedPositionView
            }
            .padding(.top, isMacOS ? 60 : 16)
            .padding(.horizontal, 16)
        }
        .background(VaultMainScreenBackground())
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
        .onChange(of: viewModel.selectedPosition) { _, _ in
            Task { await refresh() }
        }
        .crossPlatformSheet(isPresented: $showPositionSelection) {
            DefiChainSelectPositionsScreen(
                viewModel: viewModel,
                isPresented: $showPositionSelection
            )
        }
        .crossPlatformToolbar(ignoresTopEdge: true) {}
        .withLoading(isLoading: $isLoading)
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
                DefiChainBondedView(
                    viewModel: bondViewModel,
                    coin: group.nativeCoin,
                    onBond: { onTransactionToPresent(.bond(coin: group.nativeCoin.toCoinMeta(), node: $0?.address)) },
                    onUnbond: { onTransactionToPresent(.unbond(node: $0)) },
                    emptyStateView: { emptyStateView }
                )
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
        case .stake, .compound:
            onTransactionToPresent(.stake(coin: position.coin, defaultAutocompound: false))
        case .index:
            onTransactionToPresent(.mint(coin: coin(for: position.coin), yCoin: position.coin))
        }
    }
    
    func onUnstake(position: StakePosition) {
        switch position.type {
        case .stake, .compound:
            onTransactionToPresent(
                .unstake(
                    coin: position.coin,
                    defaultAutocompound: false,
                    availableToUnstake: position.availableToUnstake
                )
            )
        case .index:
            onTransactionToPresent(.redeem(coin: coin(for: position.coin), yCoin: position.coin))
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
                Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0), location: 1.00),
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
        Task { await viewModel.refresh() }
        switch viewModel.selectedPosition {
        case .bond:
            await bondViewModel.refresh()
        case .stake:
            await stakeViewModel.refresh()
        case .liquidityPool:
            await lpsViewModel.refresh()
        }
    }
    
    func update(vault: Vault) {
        viewModel.update(vault: vault)
        bondViewModel.update(vault: vault)
        lpsViewModel.update(vault: vault)
        stakeViewModel.update(vault: vault)
    }
}

#Preview {
    DefiChainMainScreen(vault: .example, group: .example)
        .environmentObject(HomeViewModel())
}
