//
//  SettingVaultRegistrationCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

import SwiftUI

struct SettingVaultRegistrationCell: View {
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack(spacing: 12) {
            iconBlock
            titleBlock
            Spacer()
            chevron
        }
        .padding(12)
        .background(Color.turquoise600)
        .cornerRadius(10)
    }
    
    var iconBlock: some View {
        Image("VultisigLogo")
            .resizable()
            .frame(width: 18, height: 18)
    }
    
    var titleBlock: some View {
        Text(NSLocalizedString("registerYourVaults", comment: ""))
            .font(theme.fonts.bodySRegular)
            .foregroundColor(.neutral900)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.body16Menlo)
            .foregroundColor(.neutral900)
    }
    
}

#Preview {
    SettingVaultRegistrationCell()
}
