//
//  LimitSwapConfirmationSheet.swift
//  VultisigApp
//

import BigInt
import SwiftUI

/// Bottom sheet presented when the user taps Place Limit Order. Mirrors the
/// Figma sign screen (vultisig-ios#4232 screen 5) — header, order summary,
/// target price + expiry, byte-cap error if applicable, "amount is correct"
/// checkbox, Sign button gated on the checkbox.
///
/// Visual fidelity to the Figma is intentionally minimal in §8.A. Real
/// Blockaid scan banner + fees grid + production-grade typography land in
/// §8.B once the user can verify on a device.
struct LimitSwapConfirmationSheet: View {

    @Bindable var vm: LimitSwapConfirmationViewModel

    let onDismiss: () -> Void
    let onSignAttempt: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            orderSummary

            detailsGrid

            if let byteCapError = vm.byteCapError {
                byteCapErrorBanner(byteCapError)
            }

            Spacer(minLength: 0)

            Checkbox(
                isChecked: Binding(
                    get: { vm.isAmountCorrectChecked },
                    set: { _ in vm.toggleAmountCorrect() }
                ),
                text: "limitSwap.confirmation.amountIsCorrect".localized
            )
            .padding(.vertical, 8)

            PrimaryButton(
                title: "limitSwap.confirmation.signTransaction".localized,
                action: { Task { await onSignAttempt() } }
            )
            .disabled(!vm.canSign)
        }
        .padding(20)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("limitSwap.confirmation.title".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.colors.textTertiary)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var orderSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("limitSwap.confirmation.subtitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)

            Text(summaryLine)
                .font(Theme.fonts.priceBodyL)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    private var detailsGrid: some View {
        VStack(spacing: 8) {
            detailRow(
                titleKey: "limitSwap.confirmation.targetPrice",
                value: targetPriceLabel
            )
            detailRow(
                titleKey: "limitSwap.confirmation.expiry",
                value: expiryLabel
            )
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(titleKey: String, value: String) -> some View {
        HStack {
            Text(titleKey.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    private func byteCapErrorBanner(_ error: LimitSwapMemoError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.colors.alertError)

            Text(byteCapErrorMessage(error))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.colors.bgError)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Formatting helpers

    private var summaryLine: String {
        "\(vm.draft.fromAsset.ticker) → \(vm.draft.toAsset.ticker)"
    }

    private var targetPriceLabel: String {
        let price = NSDecimalNumber(decimal: vm.draft.targetPrice).stringValue
        return "\(price) \(vm.draft.toAsset.ticker) / \(vm.draft.fromAsset.ticker)"
    }

    private var expiryLabel: String {
        switch vm.draft.expiryHours {
        case 12: return "limitSwap.expiry.12h".localized
        case 24: return "limitSwap.expiry.24h".localized
        case 72: return "limitSwap.expiry.3d".localized
        default: return "\(vm.draft.expiryHours)h"
        }
    }

    private func byteCapErrorMessage(_ error: LimitSwapMemoError) -> String {
        switch error {
        case let .memoExceedsByteLimit(actual, limit):
            return String(
                format: "limitSwap.confirmation.byteCapError.format".localized,
                actual,
                limit
            )
        case .targetPriceOverflow:
            return "limitSwap.error.targetPriceOverflow".localized
        }
    }
}
