//
//  DefiNoonRow.swift
//  VultisigApp
//

import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-noon-row")

/// DeFi-tab list row for the Noon yield vault. Shows the deposited USDC balance
/// (seeded from cache, refreshed on appear) and the live 7d APY.
struct DefiNoonRow: View {
    let vault: Vault

    @State private var balance: Decimal?
    @State private var apy: Decimal?
    @State private var isLoading = true
    @State private var hasError = false

    private let provider = DefiYieldProviderFactory.make(.noon)

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image("usdc")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.colors.borderLight, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text("noonTitle".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text("noonRowYieldVault".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
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
                Text("-- USDC")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            } else if let balance, balance > 0 {
                HiddenBalanceText("\(balance.formatted()) USDC")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            } else {
                HiddenBalanceText("0 USDC")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            if let apy {
                Text("\(apy.formatted(.number.precision(.fractionLength(0...2))))% APY")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertSuccess)
            } else {
                Text("noonRowYieldVault".localized)
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

        async let positionTask: Void = refreshBalance()
        apy = try? await provider.apy(vault: vault)
        await positionTask
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
