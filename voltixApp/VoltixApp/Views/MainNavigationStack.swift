//
//  ContentView.swift
//  VoltixApp
//
//  Created by Johnny Luo on 28/1/2024.
//

import SwiftUI
import SwiftData

struct MainNavigationStack: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vault: [Vault]
    
    // Push/pop onto this array to control presentation overlay globally
    @State private var presentationStack: [CurrentScreen] = [.welcome]
    
    var body: some View {
        NavigationStack(path: $presentationStack) {
            VaultAssetsView(presentationStack: $presentationStack)  // Default top level
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
                    case .finishedTSSKeygen:
                        FinishedTSSKeygenView(presentationStack: $presentationStack)
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
                    }
                }
        }
    }
}

#Preview {
    MainNavigationStack()
        .modelContainer(for: Vault.self, inMemory: true)
}
