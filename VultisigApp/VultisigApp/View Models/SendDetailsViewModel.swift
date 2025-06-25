//
//  SendDetailsViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

enum SendDetailsFocusedTab {
    case Asset
    case Address
    case Amount
}

class SendDetailsViewModel: ObservableObject {
    @Published var selectedTab: SendDetailsFocusedTab = .Asset
    
    @Published var assetSetupDone: Bool = false
    @Published var addressSetupDone: Bool = false
    @Published var amountSetupDone: Bool = false
}
