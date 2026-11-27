//
//  PerpsDefiEntryRow.swift
//  VultisigApp
//
//  Perps entry in the DeFi tab, shown only when `PerpsConfig.isFeatureEnabled`.
//

import SwiftUI

struct PerpsDefiEntryRow: View {
    var body: some View {
        HStack(spacing: 12) {
            PerpsCoinBadge(coin: "HYPE", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("perpsTitle".localized)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    if showsBetaTag {
                        Text("perpsBetaTag".localized)
                            .font(Theme.fonts.caption10)
                            .foregroundStyle(Theme.colors.alertInfo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.radius.sm.shape.fill(Theme.colors.alertInfo.opacity(0.12)))
                    }
                }
                Text("perpsDefiSubtitle".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            Spacer()
            Icon(.chevronRight, color: Theme.colors.textTertiary, size: 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .commonListContainer()
    }

    private var showsBetaTag: Bool {
        #if DEBUG
        !PerpsConfig.isRecordingDemo
        #else
        true
        #endif
    }
}

#Preview {
    PerpsDefiEntryRow()
        .padding()
        .background(Theme.colors.bgPrimary)
}
