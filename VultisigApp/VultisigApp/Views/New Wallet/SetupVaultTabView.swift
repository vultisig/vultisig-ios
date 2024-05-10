//
//  SetupVaultTabView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI

struct SetupVaultTabView: View {
    @State var selectedTab: SetupVaultState = .TwoOfTwoVaults
    
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var content: some View {
        VStack {
            SetupVaultTab(selectedTab: $selectedTab)
            SetupVaultImageManager(selectedTab: $selectedTab)
            Spacer()
        }
        .padding(16)
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultTabView()
    }
}
