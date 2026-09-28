//
//  WalletConnectVerifyContextView.swift
//  VultisigApp
//

import SwiftUI

struct WalletConnectVerifyContextView: View {
    let verifyContext: WalletConnectVerifyContext?

    var body: some View {
        if let verifyContext {
            VStack(alignment: .leading, spacing: 8) {
                Text(verifyContext.titleLocalizationKey.localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(verifyContext.isWarning ? Theme.colors.alertWarning : Theme.colors.textPrimary)
                Text(String(format: verifyContext.messageLocalizationKey.localized, verifyContext.origin))
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
            .padding(12)
            .background(Theme.colors.bgSurface1)
            .clipShape(Theme.radius.md.shape)
        }
    }
}
