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
    @State var presentPeersScreen: Bool = false
    
    var body: some View {
        Screen(
            title: "importSeedphrase".localized,
            backgroundType: viewModel.state == .activeChains ? .gradient : .plain
        ) {
            Group {
                switch viewModel.state {
                case .scanningChains:
                    KeyImportScanningForChainsView()
                case .activeChains:
                    KeyImportActiveChainsView(
                        activeChains: viewModel.activeChains,
                        maxChains: viewModel.maxChains,
                        onImport: { presentPeersScreen = true },
                        onCustomize: onCustomizeChains
                    )
                case .customizeChains:
                    KeyImportCustomizeChainsView(
                        viewModel: viewModel,
                        onImport: { presentPeersScreen = true }
                    )
                }
            }
            .transition(.opacity)
        }
        .animation(.interpolatingSpring, value: viewModel.state)
        .onLoad(perform: { await viewModel.onLoad() })
        // TODO: - Remove - only for testing, should go to vault setup screen
        .navigationDestination(isPresented: $presentPeersScreen) {
            PeerDiscoveryView(
                tssType: .KeyImport,
                vault: Vault(name: "Test seedphrase " + UUID().uuidString, libType: .KeyImport),
                selectedTab: .secure,
                // TODO: - Use email and pass from form setup screen
                fastSignConfig: .init(email: "test@gmail.com", password: "t", hint: nil, isExist: false),
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
