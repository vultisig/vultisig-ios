//
//  DefiTHORChainMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiTHORChainMainScreen: View {
    @ObservedObject var vault: Vault
    
    @StateObject var viewModel = DefiTHORChainMainViewModel()
    @StateObject var bondViewModel: DefiTHORChainBondViewModel
    @State private var showPositionSelection = false
    
    // TODO: - Inject - use grouped chain from vault
    var groupedChain: GroupedChain {
        let asset = CoinMeta(chain: .thorChain, ticker: "RUNE", logo: "rune", decimals: 8, priceProviderId: "thorchain", contractAddress: "", isNativeToken: true)
        let coin = Coin(asset: asset, address: "thor1rxrvvw4xgscce7sfvc6wdpherra77932szstey", hexPublicKey: "HexPublicKeyExample")
        let groupedChain = GroupedChain(
            chain: .thorChain,
            address: "bc1psrjtwm7682v6nhx2...uwfgcfelrennd7pcvq",
            logo: "thorchain",
            count: 3,
            coins: [coin]
        )
        
        return groupedChain
    }
    
    init(vault: Vault) {
        self._bondViewModel = StateObject(wrappedValue: DefiTHORChainBondViewModel(vault: vault))
    }
    
    var body: some View {
        Screen(edgeInsets: .init(top: .zero, bottom: .zero), backgroundType: .gradient) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    DefiTHORChainBalanceView(groupedChain: groupedChain)
                    positionsSegmentedControlView
                    selectedPositionView
                }
                .padding(.top, isMacOS ? 60 : 16)
            }
        }
        .overlay(bottomGradient, alignment: .bottom)
        .onChange(of: vault) { _, vault in
            bondViewModel.update(vault: vault)
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
                    coin: groupedChain.nativeCoin
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
                DefiTHORChainLPsView(vault: vault) { _ in
                    // TODO: - Redirect to remove LP
                } onAdd: { _ in
                    // TODO: - Redirect to add LP
                }

            }
        }
        .transition(.opacity)
        .animation(.easeInOut, value: viewModel.selectedPosition)
        .gesture(
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
        )
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

#Preview {
    DefiTHORChainMainScreen(vault: .example)
        .environmentObject(HomeViewModel())
}
