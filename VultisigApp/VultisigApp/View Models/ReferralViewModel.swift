//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-03.
//

import SwiftUI

class ReferralViewModel: ObservableObject {
//    @AppStorage("showReferralCodeOnboarding") var showReferralCodeOnboarding: Bool = true
    @State var showReferralCodeOnboarding: Bool = true
    
    @Published var showReferralBannerSheet: Bool = false
    @Published var navigationToReferralOverview: Bool = false
    
    func closeBannerSheet() {
        showReferralBannerSheet = false
        navigationToReferralOverview = true
    }
}
