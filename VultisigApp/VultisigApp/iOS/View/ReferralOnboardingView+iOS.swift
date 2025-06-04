//
//  ReferralOnboardingView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-04.
//

#if os(iOS)
import SwiftUI

extension ReferralOnboardingView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("referral", comment: ""))
    }
    
    var content: some View {
        ZStack {
            Background()
            shadow
            main
        }
    }
    
    var main: some View {
        VStack {
            Spacer()
            ReferralOnboardingGuideAnimation()
            Spacer()
            button
        }
    }
}
#endif
