//
//  OnboardingView3.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-14.
//

import SwiftUI

struct OnboardingView3: View {
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
    
#if os(macOS)
    var navigationArrow: some View {
        HStack {
            previousButton
            Spacer()
            nextButton
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
    
    var nextButton: some View {
        Button(action: {
            tabIndex += 1
        }, label: {
            NavigationButton()
        })
    }
#endif
}

#Preview {
#if os(iOS)
    OnboardingView3()
#elseif os(macOS)
    OnboardingView3(tabIndex: .constant(2))
#endif
}
