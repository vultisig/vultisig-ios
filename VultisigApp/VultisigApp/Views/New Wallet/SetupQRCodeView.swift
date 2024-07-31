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
    @Binding var showSheet: Bool
    @Binding var shouldJoinKeygen: Bool
    @Binding var shouldKeysignTransaction: Bool
    
    @State var selectedTab: SetupVaultState = .TwoOfTwoVaults
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("setup", comment: "Setup title"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
    
    var view: some View {
        VStack {
            image
            messageModal
            buttons
        }
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: vault)
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = viewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
    }
    
    var image: some View {
        SetupVaultTabView(selectedTab: $selectedTab)
    }
    
    var messageModal: some View {
        WifiInstruction()
            .frame(maxHeight: 80)
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            startButton
            joinButton
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
            FilledButton(title: "start")
        }
    }
    
    var joinButton: some View {
#if os(iOS)
        Button {
            showSheet = true
        } label: {
            OutlineButton(title: "pair")
        }
#elseif os(macOS)
        NavigationLink {
            GeneralQRImportMacView(type: .NewVault)
        } label: {
            OutlineButton(title: "pair")
        }
#endif
    }
}

#Preview {
    SetupQRCodeView(
        tssType: .Keygen, 
        vault: Vault.example,
        showSheet: .constant(false),
        shouldJoinKeygen: .constant(false),
        shouldKeysignTransaction: .constant(false)
    )
    .environmentObject(HomeViewModel())
}
