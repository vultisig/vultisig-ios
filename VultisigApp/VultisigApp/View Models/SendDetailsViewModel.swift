//
//  SendDetailsViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

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

    /// Detects the chain from the scanned address and switches if found in vault
    /// Returns the detected coin if found, or nil if no match
    func detectAndSwitchChain(from address: String, vault: Vault, currentChain: Chain, tx: SendTransaction) -> Coin? {
        // Use AddressService to detect the chain
        guard let detectedChain = AddressService.detectChain(from: address, vault: vault, currentChain: currentChain) else {
            return nil
        }

        // Find the native token for the detected chain
        guard let coin = vault.coins.first(where: { $0.chain == detectedChain && $0.isNativeToken == true }) else {
            return nil
        }

        // Switch to the detected chain's native token
        selectedChain = detectedChain
        tx.coin = coin
        tx.fromAddress = coin.address

        return coin
    }
}
