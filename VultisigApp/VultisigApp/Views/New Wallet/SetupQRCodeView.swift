//
//  SetupQRCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftData
import SwiftUI

struct SetupQRCodeView: View {
    let tssType: TssType
    let vault: Vault?

    @State var selectedTab: SetupVaultState = .fast
    @State var showSheet: Bool = false
    @State var shouldJoinKeygen = false

    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        content
            .sensoryFeedback(.selection, trigger: selectedTab)
    }
    
    var view: some View {
        VStack {
            tabView
            button
        }
    }
    
    var tabView: some View {
        SetupVaultTabView(selectedTab: $selectedTab)
    }
    
    var button: some View {
        startButton
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
    }
    
    var startButton: some View {
        PrimaryNavigationButton(title: "next") {
            if tssType == .Keygen {
                NewWalletNameView(
                    tssType: tssType,
                    selectedTab: selectedTab,
                    name: Vault.getUniqueVaultName(modelContext: modelContext, state: selectedTab)
                )
            } else if let vault {
                if selectedTab.isFastVault {
                    FastVaultEmailView(
                        tssType: tssType,
                        vault: vault,
                        selectedTab: selectedTab
                    )
                } else {
                    PeerDiscoveryView(
                        tssType: tssType,
                        vault: vault,
                        selectedTab: selectedTab, 
                        fastSignConfig: nil
                    )
                }
            }
        }
    }
}

#Preview {
    SetupQRCodeView(
        tssType: .Keygen, 
        vault: Vault.example
    )
    .environmentObject(HomeViewModel())
}
