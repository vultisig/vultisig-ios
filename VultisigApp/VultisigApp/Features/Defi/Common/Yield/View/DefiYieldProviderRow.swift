//
//  DefiYieldProviderRow.swift
//  VultisigApp
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-yield-row")

/// DeFi-tab list row for a USDC yield provider (e.g. Circle). Provider-specific
/// copy and logo come from `presentation`; the deposited position is seeded from
/// the cached `YieldPosition` and refreshed on appear. One row serves every
/// provider — adding one needs no new view.
struct DefiYieldProviderRow: View {
    let vault: Vault
    let providerID: DefiYieldProviderID

    @State private var balance: Decimal?
    @State private var isLoading = true
    @State private var hasError = false

    private var provider: DefiYieldProvider { DefiYieldProviderFactory.make(providerID) }
    private var presentation: YieldPresentation { provider.presentation }

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image(presentation.rowLogoAsset)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.colors.borderLight, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.rowTitleKey.localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    if let subtitle = presentation.rowSubtitleKey {
                        Text(subtitle.localized)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                rightSideContent
                Icon(named: "chevron-right-small", color: Theme.colors.textPrimary, size: 16)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Theme.colors.bgSurface1)
        .buttonStyle(.plain)
        .task { await load() }
    }

    @ViewBuilder
    private var rightSideContent: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if isLoading {
                Text("...")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            } else if hasError {
                Text("--")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            } else {
                HiddenBalanceText((balance ?? 0).formatToFiat())
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                HiddenBalanceText("\((balance ?? 0).formatted()) USDC")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }

    @MainActor
    private func load() async {
        if let cached = YieldPositionStorageService().position(for: vault, providerID: providerID) {
            balance = cached.depositedBalance
            isLoading = false
        }

        do {
            let position = try await provider.refreshPosition(vault: vault)
            balance = position.depositedBalance
            isLoading = false
            hasError = false
        } catch {
            logger.error("\(providerID.rawValue) row balance load failed: \(error.localizedDescription)")
            isLoading = false
            if balance == nil { hasError = true }
        }
    }
}
