//
//  OnboardingView1.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-14.
//

import SwiftUI

struct OnboardingView1: View {
    var body: some View {
        VStack(spacing: 30) {
            image
            text
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var image: some View {
        Image("OnboardingImage1")
            .frame(height: 280)
    }
    
    var text: some View {
        Text(TextStore.OnboardingText1)
            .frame(maxWidth: 500)
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 50)
    }
}

#Preview {
    OnboardingView1()
}
