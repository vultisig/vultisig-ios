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
            SetupVaultTab(selectedTab: $selectedTab)
            SetupVaultImageManager(selectedTab: $selectedTab)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultTabView(selectedTab: .constant(.fast))
    }
}
