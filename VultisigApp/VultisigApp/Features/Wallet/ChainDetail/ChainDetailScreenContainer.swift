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
    @Binding var showCamera: Bool
    
    @State private var selectedTab: HomeTab = .wallet
    private let tabs: [HomeTab]
    
    @State private var showAction: Bool = false
    @State private var vaultAction: VaultAction? = nil
    @StateObject var sendTx = SendTransaction()
    
    init(group: GroupedChain, vault: Vault, showCamera: Binding<Bool>) {
        self.group = group
        self.vault = vault
        self._showCamera = showCamera
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
                        vaultAction: $vaultAction,
                        showAction: $showAction
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
        .navigationDestination(isPresented: $showAction) {
            if let vaultAction {
                VaultActionRouteBuilder().buildActionRoute(
                    action: vaultAction,
                    sendTx: sendTx,
                    vault: vault
                )
            }
        }
    }
}

#Preview {
    ChainDetailScreenContainer(
        group: .example,
        vault: .example,
        showCamera: .constant(false)
    )
}
