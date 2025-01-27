//
//  SetupVaultImageManager.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI
import RiveRuntime

struct SetupVaultAnimationManager: View {
    @Binding var selectedTab: SetupVaultState
    
    let animationVM = RiveViewModel(fileName: "ChooseVault", animationName: "Secure")
    
    var body: some View {
        animation
            .padding(.vertical, 16)
            .onChange(of: selectedTab) { oldValue, newValue in
                animationVM.play(animationName: newValue == .secure ? "Secure" : "Secure 1")
            }
    }
    
    var animation: some View {
        animationVM.view()
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultAnimationManager(selectedTab: .constant(.secure))
    }
}
