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
    @State var qrCodeResult: String? // Adiciona estado para armazenar o resultado do QR code
    
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
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
        .onChange(of: qrCodeResult) { result in
            // Lida com o resultado do QR code
            if let result = result {
                print("QR Code Result: \(result)")
                // Executa ações adicionais com o resultado
            }
        }
    }
    
    var view: some View {
        VStack {
            image
            messageModal
            buttons
        }
        .sheet(isPresented: $showSheet, content: {
            GeneralCodeScannerView(
                showSheet: $showSheet,
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: $shouldKeysignTransaction,
                qrCodeResult: $qrCodeResult // Passa o binding
            )
        })
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: getUniqueVaultName()))
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
                    vault: vault ?? Vault(name: getUniqueVaultName()),
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
            vault = Vault(name: getUniqueVaultName())
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
