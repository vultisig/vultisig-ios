//
//  OnboardingView3.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-14.
//

import SwiftUI

struct OnboardingView3: View {
    @Binding var tabIndex: Int?
    
    var body: some View {
        container
    }
    
    var content: some View {
        VStack(spacing: 30) {
            image
            text
        }
    }
    
    var image: some View {
        Image("OnboardingImage3")
            .frame(height: 280)
    }
    
    var text: some View {
        Text(NSLocalizedString("OnboardingView3Description", comment: ""))
            .frame(maxWidth: 500)
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 50)
    }
}
