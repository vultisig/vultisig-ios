//
//  OnboardingInformationRowView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/12/2025.
//

import SwiftUI

struct OnboardingInformationRowView: View {
    let title: String
    let subtitle: String
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Icon(
                named: icon,
                color: Theme.colors.alertInfo,
                size: 20
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
                
                Text(subtitle)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.footnote)
            }
        }
    }
}

#Preview {
    OnboardingInformationRowView(
        title: "twoDevices".localized,
        subtitle: "twoDevicesSubtitle".localized,
        icon: "devices"
    )
}
