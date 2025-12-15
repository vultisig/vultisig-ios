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
    let onCamera: () -> Void
    
    @State private var selectedTab: HomeTab = .wallet
    @State private var tabs: [HomeTab] = []
    
    var body: some View {
        ZStack {
            VultiTabBar(
                selectedItem: $selectedTab,
                items: tabs,
                accessory: .camera
            ) { tab in
                Group {
                    switch tab {
                    case .wallet:
                        ChainDetailScreen(group: group, vault: vault)
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
                onCamera()
            }
            .onChange(of: selectedTab) { _, tab in
                guard tab == .camera else { return }
                onCamera()
            }
            .showIf(!tabs.isEmpty)
        }
        .onLoad {
            let supportsDefiTab = CoinAction.defiChains.contains(group.chain)
            tabs = supportsDefiTab ? [.wallet, .defi] : [.wallet]
        }
    }
}

#Preview {
    ChainDetailScreenContainer(
        group: .example,
        vault: .example,
        onCamera: {}
    )
}
