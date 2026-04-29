//
//  QBTCClaimLoadingView.swift
//  VultisigApp
//

import SwiftUI

struct QBTCClaimLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("qbtcClaimLoading".localized)
                .font(Theme.fonts.bodyMRegular)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
