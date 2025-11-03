//
//  SendDetailsViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI
import WalletCore

enum SendDetailsFocusedTab: String {
    case asset
    case address
    case amount
}

class SendDetailsViewModel: ObservableObject {
    let hasPreselectedCoin: Bool
    
    @Published var selectedChain: Chain? = nil
    @Published private(set) var selectedTab: SendDetailsFocusedTab?
    
    @Published var assetSetupDone: Bool = false
    @Published var addressSetupDone: Bool = false
    @Published var amountSetupDone: Bool = false
    @Published var showCoinPickerSheet: Bool = false
    @Published var showChainPickerSheet: Bool = false
    @Published var showAddChainAlert: Bool = false
    @Published var detectedChain: Chain? = nil
    
    init(hasPreselectedCoin: Bool = false) {
        self.hasPreselectedCoin = hasPreselectedCoin
    }
    
    func onLoad() {
        if hasPreselectedCoin {
            assetSetupDone = true
            selectedTab = .address
        } else {
            selectedTab = .asset
        }
    }
    
    func onSelect(tab: SendDetailsFocusedTab) {
        switch tab {
        case .asset, .address:
            selectedTab = tab
        case .amount:
            guard addressSetupDone else {
                return
            }
            selectedTab = tab
        }
    }
    
    /// Detects the chain from the scanned address by checking against all WalletCore CoinTypes
    /// Returns the detected coin if found, or nil if no match
    func detectAndSwitchChain(from address: String, vault: Vault, currentChain: Chain, tx: SendTransaction) -> Coin? {
        print("🔍 DetectAndSwitchChain called - Address: \(address)")
        print("🔍 Current chain: \(currentChain.name)")
        
        // First check if address is valid for current chain
        if AddressService.validateAddress(address: address, chain: currentChain) {
            print("✅ Address valid for current chain, no switch needed")
            return nil
        }
        
        print("❌ Address NOT valid for current chain, searching...")
        
        // Special handling for MayaChain (check first as it's a special case)
        let isMayaAddress = AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
        if isMayaAddress {
            print("🎯 Detected MayaChain")
            return handleDetectedChain(.mayaChain, vault: vault, tx: tx)
        }
        
        // Special handling for ThorChain Stagenet
        let isStagenetAddress = AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "sthor")
        if isStagenetAddress {
            print("🎯 Detected THORChain Stagenet")
            return handleDetectedChain(.thorChainStagenet, vault: vault, tx: tx)
        }
        
        // Check if it's an EVM address (0x followed by 40 hex characters)
        if isEVMAddress(address) {
            print("🎯 Detected EVM address")
            return handleEVMAddress(address: address, vault: vault, currentChain: currentChain, tx: tx)
        }
        
        // Iterate through all WalletCore CoinTypes to find matching address
        for coinType in CoinType.allCases {
            let isValid = coinType.validate(address: address)
            if isValid {
                print("✅ Address valid for CoinType: \(coinType)")
                // Map CoinType back to Vultisig Chain
                if let chain = findChainForCoinType(coinType) {
                    print("🎯 Mapped to chain: \(chain.name)")
                    return handleDetectedChain(chain, vault: vault, tx: tx)
                } else {
                    print("⚠️ Could not map CoinType to Vultisig Chain")
                }
            }
        }
        
        print("❌ No matching chain found for address")
        return nil
    }
    
    /// Checks if an address is an EVM address (0x followed by 40 hex characters)
    private func isEVMAddress(_ address: String) -> Bool {
        let pattern = "^0x[a-fA-F0-9]{40}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(address.startIndex..., in: address)
        return regex?.firstMatch(in: address, range: range) != nil
    }
    
    /// Handles EVM address detection - all EVM chains share the same address format
    private func handleEVMAddress(address: String, vault: Vault, currentChain: Chain, tx: SendTransaction) -> Coin? {
        // If current chain is already EVM, keep it (user already on correct chain type)
        if currentChain.type == .EVM {
            return nil
        }
        
        // Find EVM chains in the vault, prioritized order
        let evmPriority: [Chain] = [
            .ethereum,      // Most common
            .base,
            .arbitrum,
            .optimism,
            .polygon,
            .avalanche,
            .bscChain,
            .blast,
            .cronosChain,
            .zksync,
            .mantle,
            .hyperliquid,
            .sei,
            .ethereumSepolia,
            .polygonV2
        ]
        
        // Try to find a prioritized EVM chain that exists in vault
        for chain in evmPriority {
            if vault.coins.contains(where: { $0.chain == chain }) {
                return handleDetectedChain(chain, vault: vault, tx: tx)
            }
        }
        
        // If no prioritized chain found, try any EVM chain in vault
        if let evmChain = vault.coins.first(where: { $0.chain.type == .EVM })?.chain {
            return handleDetectedChain(evmChain, vault: vault, tx: tx)
        }
        
        // No EVM chains in vault, suggest Ethereum as default
        return handleDetectedChain(.ethereum, vault: vault, tx: tx)
    }
    
    /// Maps a WalletCore CoinType to a Vultisig Chain
    private func findChainForCoinType(_ coinType: CoinType) -> Chain? {
        // Check all Vultisig chains to find the one with matching coinType
        for chain in Chain.allCases {
            if chain.coinType == coinType {
                return chain
            }
        }
        return nil
    }
    
    /// Handles a detected chain - switches to it if in vault, or shows alert to add it
    /// Returns the coin if found in vault, or nil if chain needs to be added
    private func handleDetectedChain(_ chain: Chain, vault: Vault, tx: SendTransaction) -> Coin? {
        print("🔄 HandleDetectedChain called for: \(chain.name)")
        
        // Find a coin with this chain in the vault (prefer native token)
        let coinInVault = vault.coins.first(where: { $0.chain == chain && $0.isNativeToken }) 
                       ?? vault.coins.first(where: { $0.chain == chain })
        
        if let coin = coinInVault {
            print("✅ Chain found in vault: \(chain.name)")
            print("🔄 Switching from \(tx.coin.chain.name) to \(coin.chain.name)")
            
            // Chain exists in vault, switch to it immediately
            selectedChain = chain
            tx.coin = coin
            tx.fromAddress = coin.address
            
            print("✅ Switch complete - tx.coin is now: \(tx.coin.chain.name)")
            return coin
        } else {
            print("⚠️ Chain NOT in vault: \(chain.name) - showing alert")
            
            // Chain not in vault, show alert to add it
            detectedChain = chain
            showAddChainAlert = true
            return nil
        }
    }
}
