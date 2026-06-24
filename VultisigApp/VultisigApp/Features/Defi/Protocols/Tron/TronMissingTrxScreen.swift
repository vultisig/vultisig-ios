//
//  TronMissingTrxScreen.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct TronMissingTrxScreen: View {
    var body: some View {
        Screen {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.fonts.largeTitle)
                    .foregroundStyle(Theme.colors.alertWarning)

                Text("tronTrxRequired".localized)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text("tronTrxRequiredDescription".localized)
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .screenTitle("tronTitle".localized)
    }
}
