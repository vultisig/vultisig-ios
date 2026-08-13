//
//  LimitNoticeRows.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Advanced Swap Queue unavailable row
//
// Shown when the `EnableAdvSwapQueue` mimir is resolved-disabled: THORChain
// isn't accepting resting `=<` limit orders right now, so placement is blocked
// (fail-closed).

struct LimitUnavailableRow: View {

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.colors.alertWarning)

            Text("limitSwap.error.advancedSwapQueueDisabled".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .overlay(
            limitNoticeCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitNoticeCornerRadius.shape)
    }
}

// MARK: - Generic blocking-notice row
//
// A message-driven sibling of `LimitUnavailableRow`, used for the pair-not-
// routable / unsupported-asset gate: the coin picker filters by CHAIN
// routability only, so a poolless pair (e.g. RUNE→VULT) slips through — the
// market-price probe's failure surfaces here and the Place CTA is disabled while
// it shows.

struct LimitNoticeRow: View {

    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.colors.alertWarning)

            Text(message)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .overlay(
            limitNoticeCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitNoticeCornerRadius.shape)
    }
}

// MARK: - Warning row

struct LimitWarningRow: View {

    let warning: LimitSwapWarning

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.colors.alertWarning)

            Text(messageKey.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .overlay(
            limitNoticeCornerRadius.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(limitNoticeCornerRadius.shape)
    }

    private var messageKey: String {
        switch warning {
        case .priceAtOrBelowMarket:
            return "limitSwap.warning.priceAtOrBelowMarket"
        case .priceFarAboveMarket:
            return "limitSwap.warning.priceFarAboveMarket"
        }
    }
}
