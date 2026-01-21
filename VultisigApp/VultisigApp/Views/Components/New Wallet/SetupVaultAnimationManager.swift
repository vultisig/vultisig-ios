//
//  SetupVaultImageManager.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI
import RiveRuntime

struct SetupVaultAnimationManager: View {
    let animationVM: RiveViewModel?

    var body: some View {
        animation
            .padding(.vertical, 16)
    }

    var animation: some View {
        animationVM?.view()
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultAnimationManager(animationVM: RiveViewModel(fileName: "ChooseVault"))
    }
}
