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
            if tabIndex != 0 {
                prevButton
            }
            
            nextButton
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
    }
    
    var prevButton: some View {
        VultiIconButton(icon: "chevron.left") {
            prevTapped()
        }
        .frame(width: 80)
        .padding(.bottom, getBottomPadding())
    }
    
    var animation: some View {
        animationVM?.view()
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
