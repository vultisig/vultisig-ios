//
//  OnboardingTextCard.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-23.
//

import SwiftUI
import RiveRuntime

struct OnboardingTextCard: View {
    let index: Int
    let animationVM: RiveViewModel
    
    @State var showText: Bool = false
    
    var body: some View {
        Group {
            Text(NSLocalizedString("OnboardingCard\(index+1)Text1", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("OnboardingCard\(index+1)Text2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("OnboardingCard\(index+1)Text3", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("OnboardingCard\(index+1)Text4", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(.body28BrockmannMedium)
        .frame(maxWidth: 512)
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
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
    OnboardingTextCard(index: 0, animationVM: RiveViewModel(fileName: "Onboarding", autoPlay: false))
}
