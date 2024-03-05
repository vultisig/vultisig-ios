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
    
    // case importFile
    // case importQRCode
    
    // Create new wallet from TSS
    case newWalletInstructions
    case peerDiscovery
    case joinKeygen
    
    // keysign
    case KeysignDiscovery(KeysignPayload)
    case JoinKeysign
    
    // Normal use (typically launches here if wallet imported/generated already)
    case vaultAssets(SendTransaction) // Main landing page for normal use. Lists ETH, BTC, ... assets.
    case menu  // Add/Export/Forget vaults
    
    // Send
    case sendInputDetails(SendTransaction)
    case sendVerifyScreen(SendTransaction) // 2nd device goes to here automatically on receiving a p2p keysign msg
    
    // Swap
    case swapInputDetails
    case swapPeerDiscovery
    case swapWaitingForPeers
    case swapVerifyScreen
    case swapDone
    
    case listVaultAssetView
    
    // transactions
    case bitcoinTransactionsListView
    case ethereumTransactionsListView
    case erc20TransactionsListView(String)
}
