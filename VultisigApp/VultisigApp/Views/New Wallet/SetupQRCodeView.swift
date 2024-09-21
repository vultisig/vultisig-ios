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
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        content
    }
    
    var view: some View {
        VStack {
            tabView
            buttons
        }
    }
    
    var tabView: some View {
        SetupVaultTabView(selectedTab: $selectedTab)
    }
    
    var buttons: some View {
        VStack(spacing: 16) {
            startButton
            if selectedTab.hasOtherDevices {
                pairButton
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
    }
    
    var startButton: some View {
        NavigationLink {
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
                        fastVaultEmail: nil,
                        fastVaultPassword: nil
                    )
                }
            }
        } label: {
            FilledButton(title: "start".uppercased())
        }
    }

    func makeVault() -> Vault {
        let vaultName = Vault.getUniqueVaultName(modelContext: modelContext, state: selectedTab)
        return Vault(name: vaultName)
    }
}

#Preview {
    SetupQRCodeView(
        tssType: .Keygen, 
        vault: Vault.example
    )
    .environmentObject(HomeViewModel())
}
