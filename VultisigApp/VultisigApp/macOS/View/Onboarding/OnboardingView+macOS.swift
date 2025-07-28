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
        OnboardingTextCard(
            index: tabIndex,
            textPrefix: "OnboardingCard"
        )
        .frame(maxWidth: .infinity)
    }
    
    var button: some View {
        HStack {
            nextButton
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
    }
    
    var animation: some View {
        animationVM?.view()
            .padding(.bottom, 100)
    }
    
    private func prevTapped() {
        guard tabIndex>0 else {
            return
        }
        
        withAnimation {
            tabIndex-=1
        }
    }
    
    func getBottomPadding() -> CGFloat {
        50
    }
}
#endif
