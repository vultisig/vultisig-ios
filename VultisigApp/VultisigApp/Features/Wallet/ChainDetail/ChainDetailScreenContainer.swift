//
//  ChainDetailScreenContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct ChainDetailScreenContainer: View {
    let chain: Chain
    @ObservedObject var vault: Vault

    @State private var selectedTab: HomeTab = .wallet
    @State private var refreshTrigger: Bool = false
    @State private var addressToCopy: Coin?
    private let tabs: [HomeTab]

    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.openURL) var openURL
    @Environment(\.router) var router

    init(chain: Chain, vault: Vault) {
        self.chain = chain
        self.vault = vault
        let supportsDefiTab = vault.availableDefiChains.contains(chain)
        var newTabs: [HomeTab] = [.wallet]
        if supportsDefiTab {
            newTabs.append(.defi)
        }
        self.tabs = newTabs
    }

    private var nativeCoin: Coin? {
        vault.nativeCoin(for: chain)
    }

    var body: some View {
        VultiTabBar(
            selectedItem: $selectedTab,
            items: tabs,
            accessory: .camera
        ) { tab in
            Group {
                switch tab {
                case .wallet:
                    if let nativeCoin {
                        ChainDetailScreen(
                            nativeCoin: nativeCoin,
                            vault: vault,
                            refreshTrigger: $refreshTrigger,
                            onAddressCopy: { addressToCopy = $0 }
                        )
                        #if os(macOS)
                        .crossPlatformToolbar(ignoresTopEdge: true) {
                            CustomToolbarItem(placement: .trailing) {
                                RefreshToolbarButton(onRefresh: { refreshTrigger.toggle() })
                            }
                            CustomToolbarItem(placement: .trailing) {
                                ToolbarButton(image: "clock.arrow.circlepath", action: onHistory) { _ in
                                    Icon(named: "clock.arrow.circlepath", color: Theme.colors.textPrimary, size: 20, isSystem: true)
                                }
                            }
                            CustomToolbarItem(placement: .trailing) {
                                ToolbarButton(image: "square-3d", action: onExplorer)
                            }
                        }
                        #endif
                    }
                case .defi:
                    switch chain {
                    case .tron:
                        TronScreen(vault: vault)
                    default:
                        DefiChainMainScreen(vault: vault, chain: chain)
                    }
                case .camera:
                    EmptyView()
                }
            }
#if os(macOS)
            .navigationBarBackButtonHidden()
#endif
        } onAccessory: {
            appViewModel.showCamera = true
        }
        .onChange(of: selectedTab) { _, tab in
            guard tab == .camera else { return }
            appViewModel.showCamera = true
        }
        #if os(iOS)
        .crossPlatformToolbar(ignoresTopEdge: true) {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "clock.arrow.circlepath", action: onHistory) { _ in
                    Icon(named: "clock.arrow.circlepath", color: Theme.colors.textPrimary, size: 20, isSystem: true)
                }
            }
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "square-3d", action: onExplorer)
            }
        }
        #endif
        .withAddressCopy(coin: $addressToCopy)
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
    }

    func onHistory() {
        router.navigate(to: TransactionHistoryRoute.list(
            pubKeyECDSA: vault.pubKeyECDSA,
            vaultName: vault.name,
            chainFilter: chain
        ))
    }

    func onExplorer() {
        guard
            let address = vault.address(for: chain),
            let url = Endpoint.getExplorerByAddressURLByGroup(chain: chain, address: address),
            let linkURL = URL(string: url)
        else { return }
        openURL(linkURL)
    }
}

#Preview {
    ChainDetailScreenContainer(
        chain: .bitcoin,
        vault: .example
    )
    .environmentObject(AppViewModel())
}
