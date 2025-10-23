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
    @State private var showPositionSelection = false
    
    init(vault: Vault, group: GroupedChain) {
        self.vault = vault
        self.group = group
        self._bondViewModel = StateObject(wrappedValue: DefiTHORChainBondViewModel(vault: vault))
        self._lpsViewModel = StateObject(wrappedValue: DefiTHORChainLPsViewModel(vault: vault))
        self._viewModel = StateObject(wrappedValue: DefiTHORChainMainViewModel(vault: vault))
    }
    
    var body: some View {
        Screen(edgeInsets: .init(top: .zero, bottom: .zero), backgroundType: .gradient) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    DefiTHORChainBalanceView(groupedChain: group)
                    positionsSegmentedControlView
                    selectedPositionView
                }
                .padding(.top, isMacOS ? 60 : 16)
            }
        }
        .overlay(bottomGradient, alignment: .bottom)
        .onLoad {
            viewModel.onLoad()
            Task { await refresh() }
        }
        .refreshable { await refresh() }
        .onChange(of: vault) { _, vault in
            viewModel.update(vault: vault)
            bondViewModel.update(vault: vault)
            lpsViewModel.update(vault: vault)
        }
        .crossPlatformSheet(isPresented: $showPositionSelection) {
            DefiTHORChainSelectPositionsScreen(
                viewModel: viewModel,
                isPresented: $showPositionSelection
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
                    coin: group.nativeCoin
                ) { _ in
                    // TODO: - Redirect to bond
                } onUnbond: { _ in
                    // TODO: - Redirect to unbond
                }
            case .stake:
                DefiTHORChainStakedView(
                    onStake: { _ in
                        // TODO: - Redirect to stake
                    },
                    onUnstake: { _ in
                        // TODO: - Redirect to unstake
                    },
                    onWithdraw: { _ in
                        // TODO: - Redirect to withdraw
                    }
                )
            case .liquidityPool:
                DefiTHORChainLPsView(
                    vault: vault,
                    viewModel: lpsViewModel,
                    onRemove: { _ in
                        // TODO: - Redirect to remove LP
                    },
                    onAdd: { _ in
                        // TODO: - Redirect to add LP
                    }
                )

            }
        }
        .transition(.opacity)
        .animation(.easeInOut, value: viewModel.selectedPosition)
        .gesture(dragGesture)
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
        // TODO: - Refresh per tab
        await viewModel.refresh()
        await bondViewModel.refresh()
        await lpsViewModel.refresh()
    }
}

#Preview {
    DefiTHORChainMainScreen(vault: .example, group: .example)
        .environmentObject(HomeViewModel())
}
