//
//  VaultMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import Foundation

final class VaultMainViewModel: ObservableObject {
    var availableActions: [CoinAction] {
        [.swap, .buy, .send, .receive]
    }
    
    @Published var selectedTab: VaultTab = .portfolio
    
    var tabs: [SegmentedControlItem<VaultTab>] = [
        SegmentedControlItem(value: .portfolio, title: "portfolio".localized),
        SegmentedControlItem(value: .nfts, title: "nfts".localized, tag: "soon".localized, isEnabled: false)
    ]
}
