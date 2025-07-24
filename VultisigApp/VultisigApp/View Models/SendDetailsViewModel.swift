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
        selectedTab = hasPreselectedCoin ? .address : .asset
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
}
