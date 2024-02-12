//
//  ContentView.swift
//  VoltixApp
//

import SwiftData
import SwiftUI

struct MainNavigationStack: View {
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject var appState: ApplicationState
    // Push/pop onto this array to control presentation overlay globally
    @State private var presentationStack: [CurrentScreen] = [.welcome]

    var body: some View {
        NavigationStack(path: $presentationStack) {
            VaultAssetsView(presentationStack: $presentationStack) // Default top level
                .navigationDestination(for: CurrentScreen.self) { screen in
                    switch screen {
                    case .welcome:
                        WelcomeView(presentationStack: $presentationStack)
                    case .startScreen:
                        StartView(presentationStack: $presentationStack)
                    case .importWallet:
                        ImportWalletView(presentationStack: $presentationStack)
                    case .importFile:
                        ImportFile(presentationStack: $presentationStack)
                    case .importQRCode:
                        ImportQRCode(presentationStack: $presentationStack)
                    case .newWalletInstructions:
                        NewWalletInstructions(presentationStack: $presentationStack, vaultName: "new vault")
                    case .peerDiscovery:
                        PeerDiscoveryView(presentationStack: $presentationStack)
                    case .finishedTSSKeygen:
                        if let currentVault = appState.currentVault {
                            FinishedTSSKeygenView(presentationStack: $presentationStack, vault: currentVault)
                        } else {
                            VaultSelectionView(presentationStack: $presentationStack)
                        }
                    case .vaultAssets:
                        VaultAssetsView(presentationStack: $presentationStack)
                    case .vaultDetailAsset(let asset):
                        VaultAssetDetailView(presentationStack: $presentationStack, type: asset)
                    case .menu:
                        MenuView(presentationStack: $presentationStack)
                    case .sendInputDetails:
                        SendInputDetailsView(presentationStack: $presentationStack)
                    case .sendPeerDiscovery:
                        SendPeerDiscoveryView(presentationStack: $presentationStack)
                    case .sendWaitingForPeers:
                        SendWaitingForPeersView(presentationStack: $presentationStack)
                    case .sendVerifyScreen:
                        SendVerifyView(presentationStack: $presentationStack)
                    case .sendDone:
                        SendDoneView(presentationStack: $presentationStack)
                    case .swapInputDetails:
                        SwapInputDetailsView(presentationStack: $presentationStack)
                    case .swapPeerDiscovery:
                        SwapPeerDiscoveryView(presentationStack: $presentationStack)
                    case .swapWaitingForPeers:
                        SwapWaitingForPeersView(presentationStack: $presentationStack)
                    case .swapVerifyScreen:
                        SwapVerifyView(presentationStack: $presentationStack)
                    case .swapDone:
                        SwapDoneView(presentationStack: $presentationStack)
                    case .vaultSelection:
                        VaultSelectionView(presentationStack: $presentationStack)
                    case .joinKeygen:
                        JoinKeygenView(presentationStack: $presentationStack)
                    case .KeysignDiscovery(let keysignMsg, let chain):
                        KeysignDiscoveryView(presentationStack: $presentationStack, keysignMessage: keysignMsg, chain: chain)
                    case .JoinKeysign:
                        JoinKeysignView(presentationStack: $presentationStack)
                    }
                }
                .onAppear(perform: {
                    if appState.currentVault == nil {
                        self.presentationStack = [CurrentScreen.welcome]
                        return
                    }
                })
        }
    }
}

#Preview {
    MainNavigationStack()
        .modelContainer(for: Vault.self, inMemory: true)
        .environmentObject(ApplicationState.shared)
}
