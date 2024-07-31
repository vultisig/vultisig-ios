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
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("setup", comment: "Setup"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
        .onAppear {
            setData()
        }
    }
    
    var view: some View {
        VStack(spacing: 12) {
            initiatingDeviceCard
            separator
            pairingDeviceCard
        }
        .padding(16)
        .sheet(isPresented: $showSheet, content: {
            GeneralCodeScannerView(
                showSheet: $showSheet,
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: $shouldKeysignTransaction
            )
        })
    }
    
    var initiatingDeviceCard: some View {
        NavigationLink {
            SetupQRCodeView(
                tssType: tssType,
                vault: vault ?? Vault(name: getUniqueVaultName()),
                showSheet: $showSheet,
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: $shouldKeysignTransaction
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
            GeneralQRImportMacView(type: .NewVault)
        } label: {
            pairingDeviceLabel
        }
#endif
    }
    
    var pairingDeviceLabel: some View {
        VaultSetupCard(
            title: "initiatingDevice",
            buttonTitle: "createQR",
            icon: "InitiatingDeviceIcon"
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
}

#Preview {
    SetupCardsView(tssType: .Keygen)
        .environmentObject(HomeViewModel())
}
