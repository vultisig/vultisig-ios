//
//  WalletConnectVerifyContextView.swift
//  VultisigApp
//

import SwiftUI

struct WalletConnectVerifyContextView: View {
    let verifyContext: WalletConnectVerifyContext?

    var body: some View {
        if let verifyContext, verifyContext.isWarning {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.colors.alertWarning)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verifyContext.titleLocalizationKey.localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.alertWarning)
                    Text(String(format: verifyContext.messageLocalizationKey.localized, verifyContext.origin))
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Color.walletConnectTextSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.walletConnectSurface)
            .overlay(
                Theme.radius.lg.shape
                    .stroke(Theme.colors.alertWarning.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Theme.radius.lg.shape)
        }
    }
}
