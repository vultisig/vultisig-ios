//
//  OnboardingTextCard.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-23.
//

import SwiftUI

struct OnboardingTextCard: View {
    let index: Int
    let textPrefix: String

    var deviceCount: String? = nil

    @State var showText: Bool = false

    var body: some View {
        Group {
            Text(NSLocalizedString("\(textPrefix)\(index+1)Text1", comment: ""))
                .foregroundColor(Theme.colors.textPrimary) +
            Text(deviceCount ?? "")
                .foregroundColor(Theme.colors.textPrimary) +
            Text(NSLocalizedString("\(textPrefix)\(index+1)Text2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("\(textPrefix)\(index+1)Text3", comment: ""))
                .foregroundColor(Theme.colors.textPrimary) +
            Text(NSLocalizedString("\(textPrefix)\(index+1)Text4", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(Theme.fonts.title1)
        .frame(maxWidth: 1024)
        .padding(.horizontal, 36)
        .padding(.bottom, 24)
        .multilineTextAlignment(.center)
        .opacity(showText ? 1 : 0)
        .offset(y: showText ? 0 : 50)
        .blur(radius: showText ? 0 : 10)
        .onAppear {
            setData()
        }
    }

    private func setData() {
        withAnimation {
            showText = true
        }
    }
}

#Preview {
    OnboardingTextCard(index: 0, textPrefix: "OnboardingCard")
}
