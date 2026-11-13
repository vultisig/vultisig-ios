//
//  SwapReworkAddGasSheet.swift
//  VultisigApp
//
//  "Add ETH for gas" (R4 1_05): two existing ways in. Receive opens the
//  vault's existing `ReceiveQRCodeBottomSheet` for the fee coin; Buy opens the
//  existing Banxa buy flow. Back on the form, the balance and quote are read
//  again on their own (`SwapReworkViewModel.refreshAfterForeground`).
//

import SwiftUI

struct SwapReworkAddGasSheet: View {
    let ticker: String
    let chainName: String
    /// "0.00088 ETH ($1.72)", nil when the shortfall is not known.
    let amountText: String?
    /// "0x4a7e…91c2"
    let addressText: String
    let onReceive: () -> Void
    let onBuy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: "swapReworkAddGasTitle".localized, ticker))
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
            if let amountText {
                Text(String(format: "swapReworkAddGasBody".localized, amountText, chainName))
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            option(
                icon: "qrcode",
                title: String(format: "swapReworkAddGasReceive".localized, ticker),
                subtitle: String(format: "swapReworkAddGasReceiveDetail".localized, addressText),
                identifier: "swapReworkAddGasReceive",
                action: onReceive
            )
            option(
                icon: "dollarsign.circle",
                title: String(format: "swapReworkAddGasBuy".localized, ticker),
                subtitle: "swapReworkAddGasBuyDetail".localized,
                identifier: "swapReworkAddGasBuy",
                action: onBuy
            )
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.colors.textTertiary)
                Text("swapReworkAddGasRecheck".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSurface1)
            .clipShape(Theme.radius.md.shape)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func option(icon: String, title: String, subtitle: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.colors.bgSurface2)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .padding(14)
            .swapReworkCard(highlighted: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
