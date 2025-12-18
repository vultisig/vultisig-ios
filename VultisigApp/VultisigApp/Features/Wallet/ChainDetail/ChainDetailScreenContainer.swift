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
    
    // TODO: - Handle
    @State var showCamera: Bool = false
    
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
            showCamera = true
        }
        .onChange(of: selectedTab) { _, tab in
            guard tab == .camera else { return }
            showCamera = true
        }
    }
}

#Preview {
    ChainDetailScreenContainer(
        group: .example,
        vault: .example
    )
}
