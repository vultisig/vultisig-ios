//
//  ReferralLaunchView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-04.
//

#if os(iOS)
import SwiftUI

extension ReferralLaunchView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("vultisig-referrals", comment: ""))
    }
    
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
}
#endif
