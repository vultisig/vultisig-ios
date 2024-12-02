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
            secureTag
//            SetupVaultTab(selectedTab: $selectedTab)
            SetupVaultImageManager(selectedTab: $selectedTab)
            secureText
        }
        .padding(.horizontal, 16)
    }
    
    var secureTag: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield")
                .foregroundColor(.turquoise600)
                .padding(12)
                .background(Color.blue600)
                .cornerRadius(8)
            
            Text(NSLocalizedString("secureVault", comment: ""))
                .foregroundColor(.neutral0)
        }
        .font(.body16MontserratBold)
    }
    
    var secureText: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<3) { _ in
                    Image(systemName: "checkmark")
                        .foregroundColor(.turquoise400)
                }
            }
            
            Text(NSLocalizedString("secureVaultTempDescription", comment: ""))
                .foregroundColor(.neutral0)
                .lineSpacing(12)
                .multilineTextAlignment(.leading)
        }
        .font(.body14MontserratSemiBold)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultTabView(selectedTab: .constant(.secure))
    }
}
