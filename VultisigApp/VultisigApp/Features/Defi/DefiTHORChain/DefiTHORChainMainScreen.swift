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
    
    var body: some View {
        GeometryReader { proxy in
            Screen(edgeInsets: .init(bottom: .zero), backgroundType: .gradient) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        DefiTHORChainBalanceView(groupedChain: groupedChain)
                        positionsSegmentedControlView
                        tabView(height: proxy.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(bottomGradient, alignment: .bottom)
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
    
    func tabView(height: CGFloat) -> some View {
        TabView(selection: $viewModel.selectedPosition) {
            ForEach(viewModel.positions.map(\.value)) { position in
                tabContent(for: position)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(position)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(minHeight: height * 1.3)
    }
    
    @ViewBuilder
    func tabContent(for position: THORChainPositionType) -> some View {
        switch position {
        case .bond:
            DefiTHORChainBondedView(coin: groupedChain.nativeCoin) { _ in
                // TODO: - Redirect to bond
            } onUnbond: { _ in
                // TODO: - Redirect to unbond
            }
        case .stake:
            DefiTHORChainStakedView()
        case .liquidityPool:
            DefiTHORChainLPsView()
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

#Preview {
    DefiTHORChainMainScreen(vault: .example)
        .environmentObject(HomeViewModel())
}
