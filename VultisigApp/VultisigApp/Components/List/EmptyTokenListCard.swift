//
//  EmptyTokenListCard.swift
//  VultisigApp
//

import SwiftUI

/// "No token found" card for an empty token list, with an optional
/// "Add custom token" link under it.
struct EmptyTokenListCard: View {
    var onAddCustomToken: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Icon(.circleDashed2, color: Theme.colors.primaryAccent4, size: 24)

                Text("noTokenFound".localized)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(Theme.radius.xl.shape.fill(Theme.colors.bgSurface1))

            if let onAddCustomToken {
                Button(action: onAddCustomToken) {
                    Text("addCustomToken".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.alertInfo)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}
