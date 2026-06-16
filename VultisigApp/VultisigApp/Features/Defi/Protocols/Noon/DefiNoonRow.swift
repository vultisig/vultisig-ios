//
//  DefiNoonRow.swift
//  VultisigApp
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-noon-row")

/// DeFi-tab list row for the Noon yield vault. Shows the deposited position's
/// USD value and USDC amount (seeded from cache, refreshed on appear).
struct DefiNoonRow: View {
    let vault: Vault

    @State private var balance: Decimal?
    @State private var isLoading = true
    @State private var hasError = false

    private let provider = DefiYieldProviderFactory.make(.noon)

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image("noon-logo")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                Text("noonVaultsRowTitle".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            Spacer()

            HStack(spacing: 8) {
                rightSideContent
                Icon(named: "chevron-right-small", color: Theme.colors.textPrimary, size: 16)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, NoonConstants.Design.horizontalPadding)
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
        if let cached = YieldPositionStorageService().position(for: vault, providerID: .noon) {
            balance = cached.depositedBalance
            isLoading = false
        }

        await refreshBalance()
    }

    @MainActor
    private func refreshBalance() async {
        do {
            let position = try await provider.refreshPosition(vault: vault)
            balance = position.depositedBalance
            isLoading = false
            hasError = false
        } catch {
            logger.error("Noon row balance load failed: \(error.localizedDescription)")
            isLoading = false
            if balance == nil { hasError = true }
        }
    }
}
