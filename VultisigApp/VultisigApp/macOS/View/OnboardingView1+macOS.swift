//
//  OnboardingView1+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension OnboardingView1 {
    @Binding var tabIndex: Int
    
    var container: some View {
        ZStack {
            content
            navigationArrow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
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
}
#endif
