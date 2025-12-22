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
    @Environment(\.router) var router
    
    var body: some View {
        Screen(
            title: viewModel.screenTitle,
            backgroundType: viewModel.state == .activeChains ? .gradient : .plain
        ) {
            Group {
                switch viewModel.state {
                case .scanningChains:
                    KeyImportScanningForChainsView(
                        onSelectChainsManually: viewModel.onSelectChainsManually
                    )
                case .activeChains:
                    KeyImportActiveChainsView(
                        activeChains: viewModel.activeChains,
                        onImport: { presentVaultSetup() },
                        onCustomize: onCustomizeChains
                    )
                case .noActiveChains:
                    KeyImportNoActiveChainsView(onAddCustomChains: viewModel.onSelectChainsManually)
                case .customizeChains:
                    KeyImportCustomizeChainsView(
                        viewModel: viewModel,
                        onImport: { presentVaultSetup() }
                    )
                }
            }
            .transition(.opacity)
        }
        .animation(.interpolatingSpring, value: viewModel.state)
        .onLoad(perform: { await viewModel.onLoad(mnemonic: mnemonic) })
    }
    
    func onCustomizeChains() {
        viewModel.state = .customizeChains
    }
    
    func presentVaultSetup() {
        router.navigate(to: OnboardingRoute.vaultSetup(
            tssType: .KeyImport,
            keyImportInput: KeyImportInput(
                mnemonic: mnemonic,
                chains: viewModel.chainsToImport
            )
        ))
    }
}

#Preview {
    KeyImportChainsSetupScreen(mnemonic: "")
}
