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
    
    var tabs: [HomeTab] {
        // Fake `camera` button on liquid glass tabs
        if #available(iOS 26.0, macOS 26.0, *) {
            return [.wallet, .earn, .camera]
        } else {
            return [.wallet, .earn]
        }
    }
    
    var body: some View {
        VultiTabBar(
            selectedItem: $selectedTab,
            items: [HomeTab.wallet, .earn],
            accessory: .camera,
        ) { tab in
            switch tab {
            case .wallet:
                VaultMainScreen(vault: vault)
            case .earn:
                EmptyView()
            case .camera:
                EmptyView()
            }
        } onAccessory: {
            onCamera()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .camera {
                selectedTab = oldValue
                onCamera()
            }
        }
    }
    func onCamera() {
        
    }
}

#Preview {
    HomeScreen(vault: .example)
        .environmentObject(HomeViewModel())
        .environmentObject(VaultDetailViewModel())
}
