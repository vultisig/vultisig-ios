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
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.colors.alertInfo)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(subtitle)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
