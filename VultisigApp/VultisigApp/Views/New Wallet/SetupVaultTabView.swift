//
//  SetupVaultTabView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI
import RiveRuntime

struct SetupVaultTabView: View {
    @Binding var selectedTab: SetupVaultState
    
    let animationVM = RiveViewModel(fileName: "ChooseVault")
    
    var body: some View {
        content
    }
    
    var content: some View {
        VStack {
            animation
            switchControl
            secureText
        }
        .padding(.horizontal, 16)
    }
    
    var animation: some View {
        SetupVaultAnimationManager(animationVM: animationVM, selectedTab: $selectedTab)
    }
    
    var switchControl: some View {
        SetupVaultSwithControl(animationVM: animationVM, selectedTab: $selectedTab)
    }
    
    var secureText: some View {
        SetupVaultSecureText(selectedTab: selectedTab)
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultTabView(selectedTab: .constant(.secure))
    }
}
