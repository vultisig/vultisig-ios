//
//  AgentAuthorizationView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/03/2026.
//

import SwiftUI

struct AgentAuthorizationView: View {
    let onAuthorize: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 56))
                .foregroundStyle(Theme.colors.turquoise)

            Text("agentAuthorizeTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("agentAuthorizeDescription".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 12) {
                PrimaryButton(title: "agentNotNow".localized, type: .outline) {
                    onDismiss()
                    dismiss()
                }

                PrimaryButton(title: "agentAuthorize".localized) {
                    onAuthorize()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)

            Button {
                // Learn more action — could open a URL or navigate to info
            } label: {
                Text("agentLearnMore".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.turquoise)
            }
            .padding(.bottom, 16)
        }
        .padding()
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

#Preview {
    AgentAuthorizationView(
        onAuthorize: {},
        onDismiss: {}
    )
}
