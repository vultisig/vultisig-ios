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
    private let tabs: [HomeTab]
    
    @EnvironmentObject var appViewModel: AppViewModel
    
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
                        nativeCoin: group.nativeCoin,
                        vault: vault
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
    }
}

#Preview {
    ChainDetailScreenContainer(
        group: .example,
        vault: .example
    )
    .environmentObject(AppViewModel())
}
