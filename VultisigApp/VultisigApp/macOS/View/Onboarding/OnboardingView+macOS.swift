//
//  OnboardingView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension OnboardingView {
    var container: some View {
        content
    }
    
    var text: some View {
        OnboardingTextCard(index: tabIndex, animationVM: animationVM)
            .frame(maxWidth: .infinity)
    }
    
    func getBottomPadding() -> CGFloat {
        50
    }
}
#endif
