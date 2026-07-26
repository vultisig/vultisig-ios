//
//  QuantumSecurityFeatureRow.swift
//  VultisigApp
//
//  Single bullet row on `QuantumSecurityIntroScreen` — icon on the
//  left, title above subtitle on the right. Three of these stack on
//  the intro screen to explain the MLDSA keygen flow.
//

import SwiftUI

struct QuantumSecurityFeatureRow: View {
    let icon: ImageResource
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Icon(icon, color: Theme.colors.alertInfo, size: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.fonts.subtitle)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(subtitle)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
