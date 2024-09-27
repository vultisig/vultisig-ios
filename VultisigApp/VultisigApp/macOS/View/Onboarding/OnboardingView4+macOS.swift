//
//  OnboardingView4+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension OnboardingView4 {
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
}

#Preview {
    OnboardingView4(tabIndex: .constant(3))
}
#endif
