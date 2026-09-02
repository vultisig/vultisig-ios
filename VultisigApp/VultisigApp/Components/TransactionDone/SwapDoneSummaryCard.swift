//
//  SwapDoneSummaryCard.swift
//  VultisigApp
//
//  Unified swap-specific summary card used by the swap done screen
//  (initiator) and the keysign-cosigner path (peer). Replaces the
//  byte-for-byte duplication between `SwapCryptoDoneView.fromToCards/summary`
//  and `JoinSwapDoneSummary.fromToCards/summary` — same from/to cards,
//  same chevron divider, same tx-hash/from/to cells, same fee surfaces.
//
//  Each caller pre-flattens its `SwapTransaction` (initiator) or
//  `KeysignPayload` (cosigner) into a `Fields` value type via one of
//  the static `init(transaction:...)` / `init(keysignPayload:...)`
//  builders. The view itself only reads `Fields` — no per-render
//  source-vs-source switching.
//

import SwiftUI

struct SwapDoneSummaryCard: View {
    struct Fields {
        let chain: Chain
        let fromCoin: Coin?
        let toCoin: Coin?
        let fromAmount: String
        let toAmount: String
        let fromFiat: String?
        let toFiat: String?
        let txHash: String
        let approveHash: String?
        let vaultName: String
        let fromAddress: String
        let toAddress: String
        /// Pre-computed network-fee string for the cosigner branch.
        /// Initiator passes `nil` and the expandable fee block from
        /// `SwapTransaction` renders instead.
        let cosignerNetworkFee: String?
        /// The original `SwapTransaction` — only set for the initiator
        /// branch (it's the source of the expandable swap+gas fees).
        let transaction: SwapTransaction?
    }

    let fields: Fields
    @Environment(\.notifyHashCopied) var notifyHashCopied

    @State private var showFees: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            fromToCards
            summaryCard
        }
    }

    // MARK: - Builders

    static func initiator(
        transaction: SwapTransaction,
        vault: Vault,
        sendSummaryViewModel: SendSummaryViewModel,
        hash: String,
        approveHash: String?
    ) -> SwapDoneSummaryCard {
        SwapDoneSummaryCard(
            fields: Fields(
                chain: transaction.fromCoin.chain,
                fromCoin: transaction.fromCoin,
                toCoin: transaction.toCoin,
                fromAmount: sendSummaryViewModel.getFromAmount(transaction),
                toAmount: sendSummaryViewModel.getToAmount(transaction),
                fromFiat: transaction.fromFiatAmount,
                toFiat: transaction.toFiatAmount,
                txHash: hash,
                approveHash: approveHash,
                vaultName: vault.name,
                fromAddress: transaction.fromCoin.address,
                toAddress: transaction.toCoin.address,
                cosignerNetworkFee: nil,
                transaction: transaction
            )
        )
    }

    static func cosigner(
        keysignPayload: KeysignPayload,
        vault: Vault,
        summaryViewModel: JoinKeysignSummaryViewModel,
        txHash: String,
        networkFee: String
    ) -> SwapDoneSummaryCard {
        let fromCoin = summaryViewModel.getFromCoin(keysignPayload)
        let toCoin = summaryViewModel.getToCoin(keysignPayload)
        return SwapDoneSummaryCard(
            fields: Fields(
                chain: keysignPayload.coin.chain,
                fromCoin: fromCoin,
                toCoin: toCoin,
                fromAmount: summaryViewModel.getFromAmount(keysignPayload),
                toAmount: summaryViewModel.getToAmount(keysignPayload),
                fromFiat: keysignPayload.fromAmountFiatString,
                toFiat: keysignPayload.toSwapAmountFiatString,
                txHash: txHash,
                approveHash: nil,
                vaultName: vault.name,
                fromAddress: fromCoin?.address ?? keysignPayload.coin.address,
                toAddress: toCoin?.address ?? keysignPayload.toAddress,
                cosignerNetworkFee: networkFee,
                transaction: nil
            )
        )
    }

    // MARK: - From / To cards

    private var fromToCards: some View {
        ZStack {
            HStack(spacing: 8) {
                getFromToCard(coin: fields.fromCoin, title: fields.fromAmount, description: fields.fromFiat, isFrom: true)
                getFromToCard(coin: fields.toCoin, title: fields.toAmount, description: fields.toFiat, isFrom: false)
            }
            chevronContent
        }
    }

    private var chevronContent: some View {
        ZStack {
            chevronIcon
            filler.offset(y: -24)
            filler.offset(y: 24)
        }
    }

    private var chevronIcon: some View {
        Image(systemName: "chevron.right")
            .foregroundStyle(Theme.colors.textButtonDisabled)
            .font(Theme.fonts.caption12)
            .bold()
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(Theme.radius.pill)
            .padding(8)
            .background(Theme.colors.bgPrimary)
            .cornerRadius(Theme.radius.pill)
            .overlay(
                Circle()
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
    }

    private var filler: some View {
        Rectangle()
            .frame(width: 6, height: 18)
            .foregroundStyle(Theme.colors.bgPrimary)
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 0) {
            getCell(title: "swapTXHash", value: fields.txHash, valueMaxWidth: 120, showCopyButton: true)

            if let approveHash = fields.approveHash, !approveHash.isEmpty {
                separator
                getCell(title: "approvalTXHash", value: approveHash, valueMaxWidth: 120, showCopyButton: true)
            }

            separator
            getCell(title: "from", value: fields.vaultName, bracketValue: fields.fromAddress, bracketMaxWidth: 120)

            separator
            getCell(title: "to", value: fields.toAddress, valueMaxWidth: 120)

            if let transaction = fields.transaction {
                if transaction.isLimit {
                    // A resting `=<` order has no market quote, so the quote-driven
                    // fee surfaces (`showTotalFees`/`showFees`/`showGas`) are all
                    // suppressed. Show its only fee — the estimated source-chain
                    // network fee — as a plain cell.
                    if !transaction.limitNetworkFeeString.isEmpty {
                        separator
                        getCell(
                            title: "networkFee",
                            value: transaction.limitNetworkFeeString,
                            bracketValue: transaction.limitNetworkFeeFiat.isEmpty ? nil : transaction.limitNetworkFeeFiat
                        )
                    }
                } else if transaction.showTotalFees {
                    separator
                    if transaction.hasFeeBreakdown {
                        totalFees(transaction)
                        otherFees(transaction, expanded: showFees)
                    } else {
                        getCell(title: "totalFee", value: transaction.totalFeeString)
                    }
                } else {
                    otherFees(transaction, expanded: true)
                }
            } else if let networkFee = fields.cosignerNetworkFee {
                separator
                getCell(title: "networkFee", value: networkFee)
            }
        }
        .padding(.horizontal, 24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(Theme.radius.xl)
        .overlay(
            Theme.radius.xl.shape
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private var separator: some View {
        Separator().opacity(0.2)
    }

    // MARK: - Initiator-only fee surfaces

    private func totalFees(_ transaction: SwapTransaction) -> some View {
        Button {
            withAnimation(.easeInOut) {
                showFees.toggle()
            }
        } label: {
            HStack {
                getCell(title: "totalFee", value: transaction.totalFeeString)
                chevron
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.up")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textPrimary)
            .rotationEffect(Angle(degrees: showFees ? 0 : 180))
    }

    private func otherFees(_ transaction: SwapTransaction, expanded: Bool) -> some View {
        HStack {
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Theme.colors.primaryAccent4)
                .padding(.bottom, 16)
            expandableFees(transaction)
        }
        .frame(maxHeight: expanded ? nil : 0)
        .clipped()
        .animation(.easeInOut, value: showFees)
    }

    private func expandableFees(_ transaction: SwapTransaction) -> some View {
        VStack(spacing: 4) {
            if transaction.showGas {
                getCell(
                    title: "networkFee",
                    value: "\(transaction.swapGasString)(\(transaction.approveFeeString))"
                )
            }
            // Gross list-rate Vultisig fee. Discounts below reconcile this row
            // to the net affiliate component retained in Total Fees.
            if transaction.showAffiliateFeeRow {
                // `swapFeeLabel` is already localized and embeds the percentage;
                // unknown-key localization intentionally echoes it unchanged.
                getCell(title: transaction.swapFeeLabel, value: transaction.baseAffiliateFee)
            }
            // Protocol Fee (native THOR/Maya outbound).
            if transaction.showProtocolFeeRow {
                getCell(title: "swap.protocol_fee", value: transaction.outboundFeeString)
            }
            if transaction.hasAppliedDiscounts {
                appliedDiscounts(transaction)
            }
            if !transaction.priceImpactString.isEmpty {
                getCell(
                    title: "swap.price_impact",
                    value: transaction.priceImpactString,
                    valueColor: transaction.priceImpactColor
                )
            }
        }
    }

    private func appliedDiscounts(_ transaction: SwapTransaction) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("swap.applied_discounts".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .padding(.vertical, 8)

            if !transaction.vultDiscount.isEmpty {
                HStack(spacing: 4) {
                    vultTierIcon(transaction)
                    Text(transaction.vultDiscountLabel)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                .font(Theme.fonts.bodySMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            if !transaction.referralDiscount.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "megaphone.fill")
                        .foregroundStyle(Theme.colors.primaryAccent4)
                    Text(transaction.referralDiscountLabel)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                .font(Theme.fonts.bodySMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func vultTierIcon(_ transaction: SwapTransaction) -> some View {
        if let tier = VultDiscountTier.from(bpsDiscount: transaction.vultDiscountBps) {
            Image(tier.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(Theme.colors.turquoise)
        }
    }

    // MARK: - Shared cells

    private func getFromToCard(coin: Coin?, title: String, description: String?, isFrom: Bool) -> some View {
        VStack(spacing: 8) {
            Text(isFrom ? "from".localized : "to".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.caption10)

            if let coin {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 32, height: 32),
                    ticker: coin.ticker,
                    tokenChainLogo: coin.tokenChainLogo
                )
                .padding(.bottom, 8)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text((description ?? "").formatToFiat(includeCurrencySymbol: true))
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(Theme.radius.xl)
        .overlay(
            Theme.radius.xl.shape
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private func getCell(
        title: String,
        value: String,
        bracketValue: String? = nil,
        valueMaxWidth: CGFloat? = nil,
        bracketMaxWidth: CGFloat? = nil,
        showCopyButton: Bool = false,
        valueColor: Color = Theme.colors.textPrimary
    ) -> some View {
        HStack {
            Text(title.localized)
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(valueColor)
                .frame(maxWidth: valueMaxWidth, alignment: .trailing)

            if let bracketValue {
                Group {
                    Text("(") +
                    Text(bracketValue) +
                    Text(")")
                }
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: bracketMaxWidth)
                .truncationMode(.middle)
                .lineLimit(1)
            }

            if showCopyButton {
                Button {
                    notifyHashCopied()
                    ClipboardManager.copyToClipboard(ExplorerLinkBuilder.getExplorerURL(chain: fields.chain, txid: value))
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodySMedium)
                }
            }
        }
        .padding(.vertical)
        .font(Theme.fonts.bodySMedium)
    }
}
