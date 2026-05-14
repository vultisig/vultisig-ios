//
//  QBTCClaimSelectionView.swift
//  VultisigApp
//
//  UTXO list + selection + total + dynamic CTA. The user can select
//  up to QBTCClaimConfig.maxClaimUtxos UTXOs. Selection is held on the
//  ViewModel so it survives a failed claim run. The CTA flips between
//  "Claim All" and "Claim X of Y" via `QBTCClaimViewModel.confirmTitle`.
//
//  Layout mirrors Figma `Claimable QBTC` (nodes 74880:112667 +
//  75164:107632): a Claimable-QBTC hero card on top, a single "Claim"
//  tab strip, a description paragraph, an "Eligible UTXOs" header, and
//  rounded UTXO rows on `bgSurface1`. Bottom-anchored PrimaryButton.
//

import SwiftUI

struct QBTCClaimSelectionView: View {
    @ObservedObject var viewModel: QBTCClaimViewModel
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage {
                        InfoBannerView(
                            description: errorMessage,
                            type: .error,
                            leadingIcon: "exclamationmark.triangle.fill"
                        )
                    }

                    heroCard

                    claimTabStrip

                    descriptionParagraph

                    eligibleHeader

                    utxoList
                }
                .padding(.bottom, 16)
            }

            PrimaryButton(title: viewModel.confirmTitle) {
                viewModel.confirmTapped()
            }
            .disabled(!viewModel.canConfirm)
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .trailing) {
            // Decorative coin image — mirrors Figma `Frame1000005808` on
            // the right of the card. Bound to the existing QBTC chain
            // asset; gracefully no-ops if the asset hasn't shipped yet.
            ZStack {
                Image("qbtc")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 71, height: 71)
                    .opacity(0.85)

                Circle()
                    .stroke(Color(red: 0.86, green: 0.61, blue: 0.1), lineWidth: 2.3)
                    .frame(width: 118, height: 118)

                Circle()
                    .stroke(Color(red: 0.86, green: 0.61, blue: 0.1), lineWidth: 0.6)
                    .shadow(color: Color(red: 0.86, green: 0.61, blue: 0.1).opacity(0.27), radius: 13.33278, x: 0, y: 0)
                    .frame(width: 145, height: 145)
            }
            .offset(x: 10, y: 30)

            VStack(alignment: .leading, spacing: 6) {
                Text("qbtcClaimHeroTitle".localized)
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(QBTCClaimAmountFormatter.formatQbtc(sats: viewModel.totalSatsAll))
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(height: 118)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Theme.colors.alertInfo.opacity(0.09),
                    Theme.colors.alertInfo.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.colors.primaryAccent4.opacity(0.17), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var claimTabStrip: some View {
        VStack(spacing: 6) {
            Text("qbtcClaimTabTitle".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Rectangle()
                .fill(Theme.colors.primaryAccent4)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var descriptionParagraph: some View {
        Text(descriptionAttributed)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var descriptionAttributed: AttributedString {
        var attributed = AttributedString("qbtcClaimDescription".localized)
        if let range = attributed.range(of: "qbtcClaimDescriptionEmphasis".localized) {
            attributed[range].foregroundColor = Theme.colors.textPrimary
        }
        return attributed
    }

    private var eligibleHeader: some View {
        Text("qbtcClaimEligibleHeader".localized)
            .font(Theme.fonts.footnote)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    private var utxoList: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.utxos, id: \.id) { utxo in
                QBTCClaimUtxoRow(
                    utxo: utxo,
                    isSelected: viewModel.selectedIds.contains(utxo.id),
                    onTap: { viewModel.toggle(utxo) }
                )
            }
        }
    }
}

struct QBTCClaimUtxoRow: View {
    let utxo: ClaimableUtxo
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                checkbox
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortTxid)
                        .font(Theme.fonts.buttonSSemibold)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(QBTCClaimAmountFormatter.formatQbtc(sats: utxo.amount))
                        .font(Theme.fonts.buttonSSemibold)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text(QBTCClaimAmountFormatter.formatBtc(sats: utxo.amount))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .padding(16)
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var checkbox: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? Theme.colors.alertSuccess : Theme.colors.textTertiary.opacity(0.6),
                    lineWidth: 1.5
                )
                .background(
                    Circle()
                        .fill(isSelected ? Theme.colors.alertSuccess.opacity(0.12) : Color.clear)
                )
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
        }
        .frame(width: 25, height: 24)
    }

    private var subtitle: String {
        if let blockHeight = utxo.blockHeight {
            return String(format: "qbtcClaimUtxoBlockFormat".localized, blockHeight)
        }
        return "qbtcClaimUtxoPending".localized
    }

    private var shortTxid: String {
        guard utxo.txid.count > 14 else { return "\(utxo.txid):\(utxo.vout)" }
        let prefix = utxo.txid.prefix(4)
        let suffix = utxo.txid.suffix(4)
        return "\(prefix)…\(suffix):\(utxo.vout)"
    }
}

/// Centralised sats → BTC/QBTC formatting for the claim flow. 8 decimals
/// (Bitcoin convention) is shared across the selection view and the
/// success view so totals always render identically.
enum QBTCClaimAmountFormatter {
    static func formatBtc(sats: UInt64) -> String {
        let btc = Decimal(sats) / Decimal(100_000_000)
        return "\(btc.formatToDecimal(digits: 8)) BTC"
    }

    static func formatQbtc(sats: UInt64) -> String {
        let qbtc = Decimal(sats) / Decimal(100_000_000)
        return "\(qbtc.formatToDecimal(digits: 8)) QBTC"
    }
}
