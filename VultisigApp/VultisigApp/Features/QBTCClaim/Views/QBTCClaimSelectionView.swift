//
//  QBTCClaimSelectionView.swift
//  VultisigApp
//
//  UTXO list + selection + total + Confirm button. The user can
//  select up to QBTCClaimConfig.maxClaimUtxos (50) UTXOs. Selection
//  is held on the ViewModel so it survives a failed claim run.
//

import SwiftUI

struct QBTCClaimSelectionView: View {
    @ObservedObject var viewModel: QBTCClaimViewModel
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            if let errorMessage {
                InfoBannerView(
                    description: errorMessage,
                    type: .error,
                    leadingIcon: "exclamationmark.triangle.fill"
                )
            }

            ScrollView {
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

            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                Text("qbtcClaimSelected".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Text("\(viewModel.selectedIds.count) / \(QBTCClaimConfig.maxClaimUtxos)")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            HStack {
                Text("qbtcClaimTotal".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Text(QBTCClaimAmountFormatter.formatBtc(sats: viewModel.totalSatsSelected))
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            PrimaryButton(title: "qbtcClaimConfirm".localized) {
                viewModel.confirmTapped()
            }
            .disabled(!viewModel.canConfirm)
        }
        .padding(.top, 8)
    }
}

struct QBTCClaimUtxoRow: View {
    let utxo: ClaimableUtxo
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.colors.primaryAccent4 : Theme.colors.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(shortTxid)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text("vout \(utxo.vout)")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer()
                Text(QBTCClaimAmountFormatter.formatBtc(sats: utxo.amount))
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var shortTxid: String {
        guard utxo.txid.count > 14 else { return utxo.txid }
        let prefix = utxo.txid.prefix(8)
        let suffix = utxo.txid.suffix(6)
        return "\(prefix)…\(suffix)"
    }
}

/// Centralised sats → BTC formatting for the claim flow. 8 decimals
/// (Bitcoin convention) is shared across the selection view and the
/// success view so totals always render identically.
enum QBTCClaimAmountFormatter {
    static func formatBtc(sats: UInt64) -> String {
        let btc = Decimal(sats) / Decimal(100_000_000)
        return "\(btc.formatToDecimal(digits: 8)) BTC"
    }
}
