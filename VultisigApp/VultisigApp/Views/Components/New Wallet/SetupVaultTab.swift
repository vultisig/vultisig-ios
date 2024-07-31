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
        .padding(.top, 20)
    }
    
    private func getCell(for state: SetupVaultState) -> some View {
        Button {
            withAnimation {
                selectedTab = state
            }
        } label: {
            getLabel(for: state)
        }
    }
    
    private func getLabel(for state: SetupVaultState) -> some View {
        ZStack {
            if selectedTab==state {
                Text(NSLocalizedString(state.rawValue, comment: ""))
                    .font(.body16MontserratBold)
                    .foregroundColor(.blue800)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LinearGradient.primaryGradientHorizontal)
                    .cornerRadius(30)
            } else {
                OutlineButton(title: state.rawValue, gradient: .primaryGradientHorizontal)
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
