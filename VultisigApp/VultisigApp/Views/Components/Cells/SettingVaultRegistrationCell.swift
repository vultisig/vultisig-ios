//
//  SettingVaultRegistrationCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

import SwiftUI

struct SettingVaultRegistrationCell: View {

    var body: some View {
        HStack(spacing: 12) {
            iconBlock
            titleBlock
            Spacer()
            chevron
        }
        .padding(12)
        .background(Theme.colors.bgButtonPrimary)
        .cornerRadius(10)
    }

    var iconBlock: some View {
        Image("VultisigLogo")
            .resizable()
            .frame(width: 18, height: 18)
    }

    var titleBlock: some View {
        Text(NSLocalizedString("registerYourVaults", comment: ""))
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textDark)
    }

    var chevron: some View {
        Image(systemName: "chevron.right")
            .font(Theme.fonts.bodyMRegular)
            .foregroundColor(Theme.colors.textDark)
    }

}

#Preview {
    SettingVaultRegistrationCell()
}
