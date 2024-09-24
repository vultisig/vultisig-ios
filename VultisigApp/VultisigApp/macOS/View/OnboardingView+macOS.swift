//
//  OnboardingView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension OnboardingView {
    var container: some View {
        content
    }
    
    var tabs: some View {
        ZStack {
            switch tabIndex {
            case 0:
                OnboardingView1(tabIndex: $tabIndex)
            case 1:
                OnboardingView2(tabIndex: $tabIndex)
            case 2:
                OnboardingView3(tabIndex: $tabIndex)
            default:
                OnboardingView4(tabIndex: $tabIndex)
            }
        }
    }
    
    var buttons: some View {
        setupVaultButton
            .padding(.horizontal, 40)
            .padding(.bottom, 10)
    }
    
    var setupVaultButton: some View {
        Button {
            skipTapped()
        } label: {
            FilledButton(title: "setupVault")
        }
        .animation(.easeInOut, value: tabIndex)
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
        .padding(.bottom, 40)
    }
}
#endif
