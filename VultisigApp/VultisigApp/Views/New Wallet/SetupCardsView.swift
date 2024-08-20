//
//  SetupCardsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-31.
//

import SwiftUI
import SwiftData

struct SetupCardsView: View {
    let tssType: TssType
    @State var vault: Vault? = nil
    @State var showSheet = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
<<<<<<< HEAD:VultisigApp/VultisigApp/Views/New Wallet/SetupCardsView.swift
=======
    @State var shouldSendCrypto = false
    @State var selectedTab: SetupVaultState = .TwoOfTwoVaults
    @State var selectedChain: Chain? = nil
    
    @StateObject var sendTx = SendTransaction()
>>>>>>> main:VultisigApp/VultisigApp/Views/New Wallet/SetupVaultView.swift
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    
    var body: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
<<<<<<< HEAD:VultisigApp/VultisigApp/Views/New Wallet/SetupCardsView.swift
        .navigationTitle(NSLocalizedString("setup", comment: "Setup"))
=======
#if os(iOS)
        .navigationTitle(NSLocalizedString("setup", comment: "Setup title"))
>>>>>>> main:VultisigApp/VultisigApp/Views/New Wallet/SetupVaultView.swift
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
        .onAppear {
            setData()
        }
#endif
        .onAppear {
            setData()
        }
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "setup")
    }
    
    var view: some View {
        VStack(spacing: 12) {
            initiatingDeviceCard
            separator
            pairingDeviceCard
        }
<<<<<<< HEAD:VultisigApp/VultisigApp/Views/New Wallet/SetupCardsView.swift
        .padding(16)
=======
#if os(iOS)
>>>>>>> main:VultisigApp/VultisigApp/Views/New Wallet/SetupVaultView.swift
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
#endif
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
    
    var initiatingDeviceCard: some View {
        NavigationLink {
            SetupQRCodeView(
                tssType: tssType,
                vault: vault ?? Vault(name: getUniqueVaultName())
            )
        } label: {
            initiatingDeviceLabel
        }
    }
    
    var initiatingDeviceLabel: some View {
        VaultSetupCard(
            title: "initiatingDevice",
            buttonTitle: "createQR",
            icon: "InitiatingDeviceIcon"
        )
    }
    
    var pairingDeviceCard: some View {
#if os(iOS)
        Button {
            showSheet = true
        } label: {
            pairingDeviceLabel
        }
#elseif os(macOS)
        NavigationLink {
            MacScannerView(type: .NewVault, sendTx: sendTx)
        } label: {
            pairingDeviceLabel
        }
#endif
    }
    
    var pairingDeviceLabel: some View {
        VaultSetupCard(
            title: "pairingDevice",
            buttonTitle: "scanQR",
            icon: "PairingDeviceIcon"
        )
    }
    
    var separator: some View {
        HStack(spacing: 18) {
            GradientSeparator(opacity: 0.1)
            orText
            GradientSeparator(opacity: 0.1)
        }
    }
    
    var orText: some View {
        Text(NSLocalizedString("or", comment: ""))
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
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
<<<<<<< HEAD:VultisigApp/VultisigApp/Views/New Wallet/SetupCardsView.swift
=======
    
    private func setupTransaction() {
        let selectedGroup = vaultDetailViewModel.selectedGroup
        
        guard let selectedGroup, let activeCoin = selectedGroup.coins.first(where: { $0.isNativeToken }) else {
            return
        }
        
        sendTx.reset(coin: activeCoin)
    }
>>>>>>> main:VultisigApp/VultisigApp/Views/New Wallet/SetupVaultView.swift
}

#Preview {
    SetupCardsView(tssType: .Keygen)
        .environmentObject(HomeViewModel())
}
