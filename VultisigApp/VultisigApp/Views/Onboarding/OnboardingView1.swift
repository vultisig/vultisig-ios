//
//  OnboardingView1.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-14.
//

import SwiftUI

struct OnboardingView1: View {
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
        Image("OnboardingImage1")
            .frame(height: 280)
    }
    
    var text: some View {
        Text(NSLocalizedString("OnboardingView1Description", comment: ""))
            .frame(maxWidth: 500)
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 50)
    }
    
#if os(macOS)
    var navigationArrow: some View {
        HStack {
            NavigationButton().opacity(0)
            Spacer()
            nextButton
        }
        .padding(.horizontal, 30)
    }
    
    var nextButton: some View {
        Button(action: {
            tabIndex += 1
        }, label: {
            NavigationButton()
        })
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
#endif
}

#Preview {
#if os(iOS)
    OnboardingView1()
#elseif os(macOS)
    OnboardingView1(tabIndex: .constant(0))
#endif
}
