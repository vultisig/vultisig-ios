//
//  KeyImportChainsSetupScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import SwiftUI

struct KeyImportChainsSetupScreen: View {
    let mnemonic: String
    
    @StateObject var viewModel = KeyImportChainsSetupViewModel()
    @State var presentVaultSetup: Bool = false
    
    var body: some View {
        Screen(title: "importSeedphrase".localized) {
            Group {
                switch viewModel.state {
                case .scanningChains:
                    KeyImportScanningForChainsView()
                case .activeChains:
                    KeyImportActiveChainsView(
                        activeChains: viewModel.activeChains,
                        maxChains: viewModel.maxChains,
                        onImport: { presentVaultSetup = true },
                        onCustomize: onCustomizeChains
                    )
                case .customizeChains:
                    KeyImportCustomizeChainsView(
                        viewModel: viewModel,
                        onImport: { presentVaultSetup = true }
                    )
                }
            }
            .transition(.opacity)
        }
        .animation(.interpolatingSpring, value: viewModel.state)
        .onLoad(perform: { await viewModel.onLoad(mnemonic: mnemonic) })
        .navigationDestination(isPresented: $presentVaultSetup) {
            VaultSetupScreen(
                tssType: .KeyImport,
                keyImportInput: KeyImportInput(
                    mnemnonic: mnemonic,
                    chains: viewModel.chainsToImport
                )
            )
        }
    }
    
    func onCustomizeChains() {
        viewModel.state = .customizeChains
    }
}

#Preview {
    KeyImportChainsSetupScreen(mnemonic: "")
}
