//
//  HiddenBalanceText.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct HiddenBalanceText: View {
    let text: String

    @EnvironmentObject var homeViewModel: HomeViewModel

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(homeViewModel.hideVaultBalance ? String.hideBalanceText : text)
    }
}

#Preview {
    HiddenBalanceText("Test test")
        .environmentObject(HomeViewModel())
}
