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
    
    @State var width: CGFloat = .zero
    
    var body: some View {
        ZStack {
            capsule
            content
        }
        .padding(6)
        .background(Color.blue400)
        .cornerRadius(100)
        .frame(height: 56)
    }
    
    var capsule: some View {
        HStack {
            RoundedRectangle(cornerRadius: 100)
                .foregroundColor(.blue600)
                .frame(width: (width/2))
                .offset(x: selectedTab == .secure ? 0 : (width/2))
            
            Spacer()
        }
    }
    
    var content: some View {
        GeometryReader { size in
            HStack {
                getButton(for: .secure)
                getButton(for: .fast)
            }
            .onAppear {
                width = size.size.width
            }
        }
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
                .font(.body20Menlo)
                .foregroundColor(selectedTab == .secure ? .alertTurquoise : .neutral0)
            
            Text(NSLocalizedString("secure", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .cornerRadius(100)
    }
    
    var fastButtonLabel: some View {
        HStack(spacing: 8) {
            if selectedTab == .secure {
                boltImage
                    .foregroundColor(.neutral0)
            } else {
                boltImage
                    .foregroundStyle(LinearGradient.primaryGradient)
            }
            
            Text(NSLocalizedString("fast", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .cornerRadius(100)
    }
    
    var boltImage: some View {
        Image(systemName: "bolt")
            .font(.body20Menlo)
    }
    
    private func handleSwitch(_ option: SetupVaultState) {
        selectedTab = option
        
        if option == .secure {
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
