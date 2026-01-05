//
//  ChainDetailScreenContainer.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct ChainDetailScreenContainer: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault

    @State private var selectedTab: HomeTab = .wallet
    @State private var refreshTrigger: Bool = false
    private let tabs: [HomeTab]

    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.openURL) var openURL
    
    init(group: GroupedChain, vault: Vault) {
        self.group = group
        self.vault = vault
        let supportsDefiTab = CoinAction.defiChains.contains(group.chain)
        tabs = supportsDefiTab ? [.wallet, .defi] : [.wallet]
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
                    ChainDetailScreen(
                        group: group,
                        vault: vault,
                        refreshTrigger: $refreshTrigger
                    )
                case .defi:
                    DefiChainMainScreen(vault: vault, group: group)
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
        .crossPlatformToolbar(ignoresTopEdge: true) {
            #if os(macOS)
            CustomToolbarItem(placement: .trailing) {
                RefreshToolbarButton(onRefresh: { refreshTrigger.toggle() })
            }
            #endif
            
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "square-3d", action: onExplorer)
            }
        }
    }
    
    func onExplorer() {
        if
            let url = Endpoint.getExplorerByAddressURLByGroup(chain: group.coins.first?.chain, address: group.address),
            let linkURL = URL(string: url)
        {
            openURL(linkURL)
        }
    }
}

#Preview {
    ChainDetailScreenContainer(
        group: .example,
        vault: .example
    )
    .environmentObject(AppViewModel())
}
