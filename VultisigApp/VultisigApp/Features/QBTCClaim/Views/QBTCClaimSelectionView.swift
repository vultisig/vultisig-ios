//
//  QBTCClaimSelectionView.swift
//  VultisigApp
//
//  UTXO list + selection + total + dynamic CTA. The user can select
//  up to QBTCClaimConfig.maxClaimUtxos UTXOs. Selection is held on the
//  ViewModel so it survives a failed claim run. The CTA flips between
//  "Claim All" and "Claim X of Y" via `QBTCClaimViewModel.confirmTitle`.
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

            headerCard

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

            PrimaryButton(title: viewModel.confirmTitle) {
                viewModel.confirmTapped()
            }
            .disabled(!viewModel.canConfirm)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("qbtcClaimHeaderTitle".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Button(action: viewModel.toggleSelectAll) {
                    Text(viewModel.isAllSelected
                        ? "qbtcClaimDeselectAll".localized
                        : "qbtcClaimSelectAll".localized)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.primaryAccent4)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.utxos.isEmpty)
            }

            Text(QBTCClaimAmountFormatter.formatBtc(sats: viewModel.totalSatsAll))
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)

            Text(String(
                format: "qbtcClaimHeaderSubtitle".localized,
                viewModel.selectedIds.count,
                viewModel.utxos.count
            ))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.colors.bgSurface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
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
                    Text(subtitle)
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

    private var subtitle: String {
        if let blockHeight = utxo.blockHeight {
            return String(format: "qbtcClaimUtxoBlockFormat".localized, blockHeight)
        }
        return "qbtcClaimUtxoPending".localized
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
