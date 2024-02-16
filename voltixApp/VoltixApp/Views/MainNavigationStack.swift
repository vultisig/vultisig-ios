//
//  ContentView.swift
//  VoltixApp
//

import SwiftData
import SwiftUI

struct MainNavigationStack: View {
    @Environment(\.modelContext) private var modelContext
    @Query var vaults: [Vault]
    @EnvironmentObject var appState: ApplicationState
    // Push/pop onto this array to control presentation overlay globally
    @State private var presentationStack: [CurrentScreen] = []
    
    var body: some View {
        NavigationStack(path: $presentationStack) {
            VaultSelectionView(presentationStack: $presentationStack)
                .navigationDestination(for: CurrentScreen.self) { screen in
                    switch screen {
                    case .welcome:
                        WelcomeView(presentationStack: $presentationStack)
                    case .startScreen:
                        StartView(presentationStack: $presentationStack)
                    case .importWallet:
                        ImportWalletView(presentationStack: $presentationStack)
                    case .newWalletInstructions:
                        NewWalletInstructions(presentationStack: $presentationStack)
                    case .peerDiscovery:
                        PeerDiscoveryView(presentationStack: $presentationStack)
                    case .vaultAssets(let tx):
                        VaultAssetsView(presentationStack: $presentationStack, transactionDetailsViewModel: tx)
                    case .vaultDetailAsset(let asset):
                        VaultAssetDetailView(presentationStack: $presentationStack, type: asset)
                    case .menu:
                        MenuView(presentationStack: $presentationStack)
                    case .sendInputDetails(let tx):
                        SendInputDetailsView(presentationStack: $presentationStack, transactionDetailsViewModel: tx)
                    case .sendPeerDiscovery:
                        SendPeerDiscoveryView(presentationStack: $presentationStack)
                    case .sendWaitingForPeers:
                        SendWaitingForPeersView(presentationStack: $presentationStack)
                    case .sendVerifyScreen(let tx):
                        SendVerifyView(presentationStack: $presentationStack, viewModel: tx)
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
        }.onAppear {
            if vaults.count == 0 {
                self.presentationStack = [CurrentScreen.welcome]
            }
            // when current vault is nil , and there are already vaults, then just go to vault selection view
            if appState.currentVault == nil && vaults.count > 0 {
                self.presentationStack.append(CurrentScreen.vaultSelection)
            }
        }
    }
}

#Preview {
    MainNavigationStack()
        .modelContainer(for: Vault.self, inMemory: true)
        .environmentObject(ApplicationState.shared)
}
