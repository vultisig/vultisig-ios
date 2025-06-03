//
//  ReferralViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-03.
//

import SwiftUI

class ReferralViewModel: ObservableObject {
    @AppStorage("isReferralCodeRegistered") var isReferralCodeRegistered: Bool = false
    
    @State var showReferralOverviewSheet: Bool = true
    
    var body: some View {
        Text("Hello, World!")
    }
}
