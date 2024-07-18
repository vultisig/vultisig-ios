//
//  SettingsDefaultChainView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-17.
//

import SwiftUI

struct SettingsDefaultChainView: View {
    var body: some View {
        VStack {
            search
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("defaultChains", comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
    }
    
    var search: some View {
        Text("Search")
    }
}

#Preview {
    SettingsDefaultChainView()
}
