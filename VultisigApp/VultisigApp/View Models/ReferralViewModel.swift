//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-03.
//

import SwiftUI

class ReferralViewModel: ObservableObject {
    @AppStorage("isReferralCodeRegistered") var isReferralCodeRegistered: Bool = false
    
    @Published var showReferralOverviewSheet: Bool = false
}
