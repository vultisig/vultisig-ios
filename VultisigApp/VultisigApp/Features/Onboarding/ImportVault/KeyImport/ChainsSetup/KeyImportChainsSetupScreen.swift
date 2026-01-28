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
            showNavigationBar: false,
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
                        onImport: { presentVaultSetup(customized: false) },
                        onCustomize: onCustomizeChains,
                        viewModel: viewModel
                    )
                case .noActiveChains:
                    KeyImportNoActiveChainsView(onAddCustomChains: viewModel.onSelectChainsManually)
                case .customizeChains:
                    KeyImportCustomizeChainsView(
                        viewModel: viewModel,
                        onImport: { presentVaultSetup(customized: true) }
                    )
                }
            }
            .transition(.opacity)
        }
        .animation(.interpolatingSpring, value: viewModel.state)
        .onLoad(perform: { viewModel.onLoad(mnemonic: mnemonic) })
        .withLoading(isLoading: $viewModel.isLoading)
        .crossPlatformToolbar(viewModel.screenTitle, ignoresTopEdge: viewModel.state == .activeChains)
    }

    func onCustomizeChains() {
        viewModel.state = .customizeChains
    }

    func presentVaultSetup(customized: Bool) {
        Task {
            // Prepare chain settings with derivation paths
            let chainSettings = await viewModel.prepareChainSettings(customized: customized)

            // Navigate to device count selection screen
            await MainActor.run {
                router.navigate(to: OnboardingRoute.keyImportDeviceCount(
                    mnemonic: mnemonic,
                    chainSettings: chainSettings
                ))
            }
        }
    }
}

#Preview {
    KeyImportChainsSetupScreen(mnemonic: "")
}
