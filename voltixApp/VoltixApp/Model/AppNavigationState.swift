//
//  AppNavigationState.swift
//  VoltixApp
//

import Foundation
import SwiftUI

enum CurrentScreen: Hashable {
    
    // Onboarding
    case welcome // Welcome screen
    case startScreen  // New or Import wallet
    case vaultSelection // a list of vault for selection
    case importWallet
    
    // Create new wallet from TSS
    case newWalletInstructions
    case peerDiscovery
    case finishedTSSKeygen
    case joinKeygen
    
    // keysign
    case KeysignDiscovery(String,Chain)
    case JoinKeysign
    
    // Normal use (typically launches here if wallet imported/generated already)
    case vaultAssets  // Main landing page for normal use. Lists ETH, BTC, ... assets.
    case vaultDetailAsset(AssetType) //ETH, BTC etc.
    case menu  // Add/Export/Forget vaults
    
    // Send
    case sendInputDetails
    case sendPeerDiscovery
    case sendWaitingForPeers  // Host party waits here
    case sendVerifyScreen     // 2nd device goes to here automatically on receiving a p2p keysign msg
    case sendDone
    
    // Swap
    case swapInputDetails
    case swapPeerDiscovery
    case swapWaitingForPeers
    case swapVerifyScreen
    case swapDone
}
