//
//  SetupVaultTabView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI

struct SetupVaultTabView: View {
    @Binding var selectedTab: SetupVaultState
    
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
        SetupVaultAnimationManager(selectedTab: $selectedTab)
    }
    
    var switchControl: some View {
        SetupVaultSwithControl(selectedTab: $selectedTab)
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
