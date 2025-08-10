//
//  SetupVaultSwithControl.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-27.
//

import SwiftUI
import RiveRuntime

struct SetupVaultSwithControl: View {
    let animationVM: RiveViewModel?
    @Binding var selectedTab: SetupVaultState
        
    var body: some View {
        ZStack {
            GeometryReader { proxy in
                capsule(width: proxy.size.width)
                HStack {
                    getButton(for: .fast)
                    getButton(for: .secure)
                }
            }
        }
        .padding(6)
        .background(Theme.colors.bgTertiary)
        .cornerRadius(100)
        .frame(height: 56)
    }
    
    func capsule(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 100)
            .foregroundColor(Theme.colors.bgSecondary)
            .frame(width: width / 2)
            .offset(x: selectedTab == .fast ? 0 : width / 2)
    }
    
    private func getButton(for option: SetupVaultState) -> some View {
        Button {
            withAnimation {
                handleSwitch(option)
            }
        } label: {
            if option == .secure {
                secureButtonLabel
            } else {
                fastButtonLabel
            }
        }
    }
    
    var secureButtonLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield")
                .font(Theme.fonts.bodyLRegular)
                .foregroundColor(selectedTab == .secure ? Theme.colors.alertInfo : Theme.colors.textPrimary)
            
            Text(NSLocalizedString("secure", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .cornerRadius(100)
    }
    
    var fastButtonLabel: some View {
        HStack(spacing: 8) {
            if selectedTab == .secure {
                boltImage
                    .foregroundColor(Theme.colors.textPrimary)
            } else {
                boltImage
                    .foregroundStyle(LinearGradient.primaryGradient)
            }
            
            Text(NSLocalizedString("fast", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .cornerRadius(100)
    }
    
    var boltImage: some View {
        Image(systemName: "bolt")
            .font(Theme.fonts.bodyLRegular)
    }
    
    private func handleSwitch(_ option: SetupVaultState) {
        let oldTab = selectedTab
        selectedTab = option
        
        guard oldTab != selectedTab else { return }
        
        if option == .fast {
            animationVM?.triggerInput("Switch")
            animationVM?.triggerInput("Switch")
        } else {
            animationVM?.triggerInput("Switch")
        }
    }
}

#Preview {
    SetupVaultSwithControl(
        animationVM: RiveViewModel(fileName: "ChooseVault"),
        selectedTab: .constant(.secure)
    )
}
