//
//  AgentReauthorizeView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/03/2026.
//

import SwiftUI

struct AgentReauthorizeView: View {
    let onAuthorize: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.colors.turquoise)

            Text("agentReauthorizeTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("agentReauthorizeDescription".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 12) {
                PrimaryButton(title: "cancel".localized, type: .outline) {
                    dismiss()
                }

                PrimaryButton(title: "agentAuthorize".localized) {
                    onAuthorize()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding()
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

#Preview {
    AgentReauthorizeView(onAuthorize: {})
}
