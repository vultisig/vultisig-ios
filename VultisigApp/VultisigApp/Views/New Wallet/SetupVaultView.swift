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
    @State var shouldKeysignTransaction = false
    @State var selectedTab: SetupVaultState = .TwoOfTwoVaults
    
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("setup", comment: "Setup title"))
        .onAppear {
            setData()
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
        }
#endif
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
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: $shouldKeysignTransaction
            )
        })
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"))
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
                    vault: vault ?? Vault(name: "Main Vault"),
                    selectedTab: selectedTab
                )
            }
        } label: {
            FilledButton(title: "start")
        }
    }
    
    var joinButton: some View {
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
    
    private func getUniqueVaultName() -> String {
        let start = vaults.count
        var idx = start
        repeat {
            let vaultName = "Vault #\(idx + 1)"
            if !isVaultNameExist(name: vaultName) {
                return vaultName
            }
            idx += 1
        } while idx < 1000
        
        return "Main Vault"
    }
    private func isVaultNameExist(name: String) -> Bool{
        for item in self.vaults {
            if item.name == name && !item.pubKeyECDSA.isEmpty {
                return true
            }
        }
        return false
    }
}

#Preview {
    SetupVaultView(tssType: .Keygen)
        .environmentObject(HomeViewModel())
}
