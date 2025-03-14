//
//  OnboardingView2+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension OnboardingView2 {
    var container: some View {
        ZStack {
            content
            navigationArrow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
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
}

#Preview {
    OnboardingView2(tabIndex: .constant(1))
}
#endif
