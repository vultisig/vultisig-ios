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
            SetupVaultImageManager(selectedTab: $selectedTab)
            secureText
        }
        .padding(.horizontal, 16)
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
