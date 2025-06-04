//
//  ReferralOnboardingView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-04.
//

#if os(macOS)
import SwiftUI

extension ReferralOnboardingView {
    var container: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }
    
    var content: some View {
        ZStack {
            Background()
            shadow
            main
                .padding(40)
        }
    }
    
    var header: some View {
        GeneralMacHeader(title: "referral")
    }
    
    var main: some View {
        VStack {
            ReferralOnboardingGuideAnimation()
            Spacer()
            button
        }
    }
}
#endif
