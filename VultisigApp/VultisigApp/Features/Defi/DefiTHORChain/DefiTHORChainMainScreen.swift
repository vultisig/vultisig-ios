//
//  DefiTHORChainMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainMainScreen: View {
    @ObservedObject var vault: Vault
    let group: GroupedChain
    
    @StateObject var viewModel: DefiTHORChainMainViewModel
    @StateObject var bondViewModel: DefiTHORChainBondViewModel
    @StateObject var lpsViewModel: DefiTHORChainLPsViewModel
    @StateObject var stakeViewModel: DefiTHORChainStakeViewModel
    @State private var showPositionSelection = false
    @State private var isLoading = false
    @State private var error: HelperError?
    
    @State private var transactionToPresent: FunctionTransactionType?
    
    init(vault: Vault, group: GroupedChain) {
        self.vault = vault
        self.group = group
        self._bondViewModel = StateObject(wrappedValue: DefiTHORChainBondViewModel(vault: vault))
        self._lpsViewModel = StateObject(wrappedValue: DefiTHORChainLPsViewModel(vault: vault))
        self._viewModel = StateObject(wrappedValue: DefiTHORChainMainViewModel(vault: vault))
        self._stakeViewModel = StateObject(wrappedValue: DefiTHORChainStakeViewModel(vault: vault))
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                DefiTHORChainBalanceView(vault: vault, groupedChain: group)
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
            Task {
                await viewModel.refresh()
                await refresh()
            }
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
            DefiTHORChainSelectPositionsScreen(
                viewModel: viewModel,
                isPresented: $showPositionSelection
            )
        }
        .crossPlatformToolbar(ignoresTopEdge: true) {}
        .navigationDestination(item: $transactionToPresent) { transaction in
            FunctionTransactionScreen(vault: vault, transactionType: transaction)
        }
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
                DefiTHORChainBondedView(
                    viewModel: bondViewModel,
                    coin: group.nativeCoin,
                    onBond: { onTransactionToPresent(.bond(coin: group.nativeCoin.toCoinMeta(), node: $0?.address)) },
                    onUnbond: { onTransactionToPresent(.unbond(node: $0)) },
                    emptyStateView: { emptyStateView }
                )
            case .stake:
                DefiTHORChainStakedView(
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
                DefiTHORChainLPsView(
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
            onTransactionToPresent(.stake(coin: stakeCoin(for: position.coin), defaultAutocompound: defaultAutocompound(for: position.coin)))
        case .index:
            onTransactionToPresent(.mint(coin: coin(for: position.coin), yCoin: position.coin))
        }
    }
    
    func onUnstake(position: StakePosition) {
        switch position.type {
        case .stake, .compound:
            onTransactionToPresent(
                .unstake(coin: stakeCoin(for: position.coin), defaultAutocompound: defaultAutocompound(for: position.coin))
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
    
    func stakeCoin(for coin: CoinMeta) -> CoinMeta {
        switch coin {
        case TokensStore.stcy:
            return TokensStore.tcy
        default:
            return coin
        }
    }
    
    func defaultAutocompound(for coin: CoinMeta) -> Bool {
        switch coin {
        case TokensStore.stcy:
            return true
        default:
            return false
        }
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
                }
                isLoading = false
            }
            
            transactionToPresent = type
        }
    }
}

private extension DefiTHORChainMainScreen {
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

private extension DefiTHORChainMainScreen {
    func refresh() async {
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
    DefiTHORChainMainScreen(vault: .example, group: .example)
        .environmentObject(HomeViewModel())
}
