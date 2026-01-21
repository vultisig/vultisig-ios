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

    var view: some View {
        VStack(spacing: 0) {
            header
            progressBar
            animation
            text
            button
        }
    }

    var text: some View {
        OnboardingTextCard(
            index: tabIndex,
            textPrefix: "OnboardingCard"
        )
        .frame(maxWidth: .infinity)
        .frame(height: 100)
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
    }

    func getBottomPadding() -> CGFloat {
        50
    }
}
#endif
