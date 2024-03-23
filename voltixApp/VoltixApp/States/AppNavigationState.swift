//
//  AppNavigationState.swift
//  VoltixApp
//

import Foundation
import SwiftUI

enum CurrentScreen: Hashable {
    // Onboarding
    case welcome // Welcome screen
    case startScreen // New or Import wallet
    case vaultSelection // a list of vault for selection
    case importWallet
    
    // case importFile
    // case importQRCode
    
    // Create new wallet from TSS
    case newWalletInstructions
    case peerDiscovery(vault: Vault, tssType: TssType)
    case joinKeygen(Vault)
    
    // keysign
    case KeysignDiscovery(KeysignPayload)
    case JoinKeysign
    
    // Normal use (typically launches here if wallet imported/generated already)
    case vaultAssets(SendTransaction) // Main landing page for normal use. Lists ETH, BTC, ... assets.
    case menu // Add/Export/Forget vaults
    
    // Swap
    case swapInputDetails
    case swapPeerDiscovery
    case swapWaitingForPeers
    case swapVerifyScreen
    case swapDone
    
    case listVaultAssetView
    
    // transactions
    case bitcoinTransactionsListView(SendTransaction)
    case ethereumTransactionsListView
    case erc20TransactionsListView(String)
}
