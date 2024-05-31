//
//  SetupVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftData
import SwiftUI

struct SetupVaultView: View {
    let tssType: TssType
    
    @Query var vaults: [Vault]
    
    @State var vault: Vault? = nil
    @State var showSheet = false
    @State var shouldJoinKeygen = false
    @State var selectedTab: SetupVaultState = .TwoOfTwoVaults
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("setup", comment: "Setup title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
        }
        .onAppear {
            setData()
        }
    }
    
    var view: some View {
        VStack {
            image
            messageModal
            Spacer()
            buttons
        }
        .sheet(isPresented: $showSheet, content: {
            GeneralCodeScannerView(
                showSheet: $showSheet,
                shouldNavigate: $shouldJoinKeygen
            )
        })
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"), shouldJoinKeygen: shouldJoinKeygen)
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
                    vault: vault ?? Vault(name: "Main Vault"),
                    selectedTab: selectedTab
                )
            }
        } label: {
            FilledButton(title: "start")
        }
    }
    
    var joinButton: some View {
//        NavigationLink {
//            JoinKeygenView(vault: vault ?? Vault(name: "Main Vault"))
//        } label: {
//            OutlineButton(title: "pair")
//        }
//        
        Button {
            showSheet = true
        } label: {
            OutlineButton(title: "pair")
        }
    }
    
    private func setData() {
        if vault == nil {
            vault = Vault(name: "Vault #\(vaults.count + 1)")
        }
    }
}

#Preview {
    SetupVaultView(tssType: .Keygen)
        .environmentObject(DeeplinkViewModel())
}
