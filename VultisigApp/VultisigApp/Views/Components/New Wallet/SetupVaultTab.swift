//
//  SetupVaultTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI

struct SetupVaultTab: View {
    @Binding var selectedTab: SetupVaultState
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(SetupVaultState.allCases, id: \.self) { type in
                getCell(for: type)
            }
        }
    }
    
    private func getCell(for state: SetupVaultState) -> some View {
        Button {
            withAnimation {
                selectedTab = state
            }
        } label: {
            VStack(spacing: 10) {
                Text(NSLocalizedString(state.rawValue, comment: ""))
                    .font(selectedTab==state ? .body14MontserratMedium : .body14Montserrat)
                    .foregroundColor(.neutral0)
                
                RoundedRectangle(cornerRadius: 10)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.neutral0)
                    .opacity(selectedTab==state ? 1 : 0)
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultTab(selectedTab: .constant(.TwoOfTwoVaults))
    }
}
