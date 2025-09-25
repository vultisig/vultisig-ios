//
//  HomeScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct HomeScreen: View {
    let vault: Vault
    @State private var selectedTab: HomeTab = .wallet
    @State var vaultRoute: VaultMainRoute?
    
    // Properties for QR Code scanner
    @State var showScanner: Bool = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    @State var shouldSendCrypto = false
    @StateObject var sendTx = SendTransaction()
    @State var selectedChain: Chain? = nil
    
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        VultiTabBar(
            selectedItem: $selectedTab,
            items: [HomeTab.wallet, .earn],
            accessory: .camera,
        ) { tab in
            switch tab {
            case .wallet:
                VaultMainScreen(vault: vault, routeToPresent: $vaultRoute)
            case .earn:
                EmptyView()
            case .camera:
                EmptyView()
            }
        } onAccessory: {
            onCamera()
        }
        .sensoryFeedback(homeViewModel.showAlert ? .stop : .impact, trigger: homeViewModel.showAlert)
        .customNavigationBarHidden(true)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .camera {
                selectedTab = oldValue
                onCamera()
            }
        }
        .navigationDestination(item: $vaultRoute) {
            buildVaultRoute(route: $0)
        }
        .sheet(isPresented: $showScanner, content: {
            GeneralCodeScannerView(
                showSheet: $showScanner,
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: $shouldKeysignTransaction,
                shouldSendCrypto: $shouldSendCrypto,
                selectedChain: $selectedChain,
                sendTX: sendTx
            )
        })
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"), selectedVault: vault)
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = homeViewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
    }
    
    func onCamera() {
        showScanner = true
    }
}

extension HomeScreen {
    @ViewBuilder
    func buildVaultRoute(route: VaultMainRoute) -> some View {
        switch route {
        case .chainDetail(let groupedChain):
            ChainDetailScreen(group: groupedChain, vault: vault)
        case .settings:
            SettingsMainScreen()
        case .createVault:
            CreateVaultView(selectedVault: vault, showBackButton: true)
        case .mainAction(let action):
            buildActionRoute(action: action)
        }
    }
    
    @ViewBuilder
    func buildActionRoute(action: CoinAction) -> some View {
        switch action {
        case .send:
            SendRouteBuilder().buildDetailsScreen(
                coin: vaultDetailViewModel.selectedGroup?.nativeCoin,
                hasPreselectedCoin: false,
                tx: sendTx,
                vault: vault
            )
        case .swap:
            if let fromCoin = vaultDetailViewModel.selectedGroup?.nativeCoin {
                SwapCryptoView(fromCoin: fromCoin, vault: vault)
            }
        case .deposit, .bridge, .memo:
            FunctionCallView(
                tx: sendTx,
                vault: vault,
                coin: vaultDetailViewModel.selectedGroup?.nativeCoin
            )
        case .buy:
            SendRouteBuilder().buildBuyScreen(
                address: vaultDetailViewModel.selectedGroup?.address ?? "",
                blockChainCode: vaultDetailViewModel.selectedGroup?.chain.banxaBlockchainCode ?? "",
                coinType: vaultDetailViewModel.selectedGroup?.nativeCoin.ticker ?? ""
            )
        case .sell, .receive:
            // TODO: - Add
            fatalError("Not implemented yet")
        }
    }
}

#Preview {
    HomeScreen(vault: .example)
        .environmentObject(HomeViewModel())
        .environmentObject(VaultDetailViewModel())
}
