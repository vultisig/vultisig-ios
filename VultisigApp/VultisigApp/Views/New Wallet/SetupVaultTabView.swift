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
        VStack {
            SetupVaultTab(selectedTab: $selectedTab)
        }
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultTabView()
    }
}
