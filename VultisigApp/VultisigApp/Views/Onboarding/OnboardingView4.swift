//
//  OnboardingView4.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-04.
//

import SwiftUI

struct OnboardingView4: View {
#if os(macOS)
    @Binding var tabIndex: Int
#endif
    
    var body: some View {
        ZStack {
            content
#if os(macOS)
            navigationArrow
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var content: some View {
        VStack(spacing: 30) {
            image
            text
        }
    }
    
    var image: some View {
        Image("OnboardingImage4")
            .frame(height: 280)
    }
    
    var text: some View {
        Text(NSLocalizedString("OnboardingView4Description", comment: ""))
            .frame(maxWidth: 500)
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 50)
    }
    
#if os(macOS)
    var navigationArrow: some View {
        HStack {
            previousButton
            Spacer()
            previousButton.opacity(0)
        }
        .padding(.horizontal, 30)
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
    
    var previousButton: some View {
        Button(action: {
            tabIndex -= 1
        }, label: {
            NavigationButton(isLeft: true)
        })
    }
#endif
}

#Preview {
#if os(iOS)
    OnboardingView4()
#elseif os(macOS)
    OnboardingView4(tabIndex: .constant(3))
#endif
}
