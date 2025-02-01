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
            textPrefix: "OnboardingCard",
            animationVM: animationVM
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
        Button {
            prevTapped()
        } label: {
            FilledButton(icon: "chevron.left")
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
        .frame(width: 80)
        .padding(.bottom, getBottomPadding())
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
