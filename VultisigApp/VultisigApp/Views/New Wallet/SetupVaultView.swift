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
    @State var vault: Vault? = nil
    @State var showSheet = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    @State var shouldSendCrypto = false
    @State var selectedTab: SetupVaultState = .TwoOfTwoVaults
    @State var selectedChain: Chain? = nil
    
    @StateObject var sendTx = SendTransaction()
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    
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
                shouldSendCrypto: $shouldSendCrypto,
                selectedChain: $selectedChain,
                sendTX: sendTx
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
        .navigationDestination(isPresented: $shouldSendCrypto) {
            if let vault = viewModel.selectedVault {
                SendCryptoView(
                    tx: sendTx,
                    vault: vault,
                    selectedChain: selectedChain
                )
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
    
    private func setData() {
        if vault == nil {
            vault = Vault(name: getUniqueVaultName())
        }
        setupTransaction()
    }
    
    private func getUniqueVaultName() -> String {
        let fetchVaultDescriptor = FetchDescriptor<Vault>()
        do{
            let vaults = try modelContext.fetch(fetchVaultDescriptor)
            let start = vaults.count
            var idx = start
            repeat {
                let vaultName = "Vault #\(idx + 1)"
                let vaultExist = vaults.contains {v in
                    v.name == vaultName && !v.pubKeyECDSA.isEmpty
                }
                if !vaultExist {
                    return vaultName
                }
                idx += 1
            } while idx < 1000
        }
        catch {
            print("fail to load all vaults")
        }
        return "Main Vault"
    }
    
    private func setupTransaction() {
        let selectedGroup = vaultDetailViewModel.selectedGroup
        
        guard let selectedGroup, let activeCoin = selectedGroup.coins.first(where: { $0.isNativeToken }) else {
            return
        }
        
        sendTx.reset(coin: activeCoin)
    }
}

#Preview {
    SetupVaultView(tssType: .Keygen)
        .environmentObject(HomeViewModel())
}
