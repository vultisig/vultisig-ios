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
    
    let animationVM = RiveViewModel(fileName: "ChooseVault")
    
    var body: some View {
        VStack {
            animation
                .padding(.vertical, 16)
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
