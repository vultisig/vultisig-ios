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
    let vault: Vault
    
    @State var selectedTab: SetupVaultState = .TwoOfTwoVaults
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationTitle(NSLocalizedString("setup", comment: "Setup title"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
    
    var view: some View {
        VStack {
            context
            image
            button
        }
    }
    
    var context: some View {
        Text(NSLocalizedString("selectYourVaultType", comment: ""))
            .font(.body14Menlo)
            .foregroundColor(.neutral0)
            .padding(.top, 10)
    }
    
    var image: some View {
        SetupVaultTabView(selectedTab: $selectedTab)
    }
    
    var button: some View {
        VStack(spacing: 20) {
            startButton
        }
        .padding(40)
    }
    
    var startButton: some View {
        NavigationLink {
            if tssType == .Keygen {
                NewWalletNameView(
                    tssType: tssType,
                    vault: vault,
                    selectedTab: selectedTab
                )
            } else {
                PeerDiscoveryView(
                    tssType: tssType,
                    vault: vault,
                    selectedTab: selectedTab
                )
            }
        } label: {
            FilledButton(title: "start".uppercased())
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
