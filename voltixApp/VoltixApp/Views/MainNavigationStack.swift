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
    @State private var presentationStack: [CurrentScreen] = []
    @ObservedObject var unspentOutputsViewModel = UnspentOutputsViewModel()
    
    var body: some View {
        NavigationStack(path: $presentationStack) {
            WelcomeView(
                presentationStack: $presentationStack
//                appState: _appState,
//                unspentOutputsViewModel: unspentOutputsViewModel,
//                transactionDetailsViewModel: TransactionDetailsViewModel()
            )
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
                        VaultSelectionView(appState: _appState, unspentOutputsViewModel: unspentOutputsViewModel, presentationStack: $presentationStack)
                    }
                case .vaultAssets(let tx):
                    VaultAssetsView(presentationStack: $presentationStack, unspentOutputsViewModel: unspentOutputsViewModel, transactionDetailsViewModel: tx)
                case .vaultDetailAsset(let asset):
                    VaultAssetDetailView(presentationStack: $presentationStack, type: asset)
                case .menu:
                    MenuView(presentationStack: $presentationStack)
                case .sendInputDetails(let tx):
                    SendInputDetailsView(presentationStack: $presentationStack, unspentOutputsViewModel: unspentOutputsViewModel, transactionDetailsViewModel: tx)
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
                    VaultSelectionView(appState: _appState, unspentOutputsViewModel: unspentOutputsViewModel, presentationStack: $presentationStack)
                case .joinKeygen:
                    JoinKeygenView(presentationStack: $presentationStack)
                case .KeysignDiscovery(let keysignMsg, let chain):
                    KeysignDiscoveryView(presentationStack: $presentationStack, keysignMessage: keysignMsg, chain: chain)
                case .JoinKeysign:
                    JoinKeysignView(presentationStack: $presentationStack)
                }
            }
        }
    }
}

#Preview {
    MainNavigationStack()
        .modelContainer(for: Vault.self, inMemory: true)
        .environmentObject(ApplicationState.shared)
}
