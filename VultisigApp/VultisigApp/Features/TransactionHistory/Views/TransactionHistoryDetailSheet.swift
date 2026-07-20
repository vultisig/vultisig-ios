//
//  TransactionHistoryDetailSheet.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryDetailSheet: View {
    let transaction: TransactionHistoryData
    /// The order behind this row, for `.limit` rows. Carries the target price,
    /// the expiry countdown and the fill split — none of which exist on
    /// `TransactionHistoryItem`. `nil` on a co-signer, which never persists a
    /// `LimitOrder`; the sheet degrades to what the row itself knows.
    var limitOrder: LimitOrderDetails?

    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss

    /// Drives the live expiry countdown. A resting order's chip has to tick on
    /// its own — nothing else republishes between the tracker's 60s polls.
    @State private var now = Date()

    private var isLimit: Bool { transaction.type == .limit }

    /// A limit order and a swap share the from/to header pair: both express an
    /// intent to trade one asset for another.
    private var showsFromToCards: Bool {
        transaction.type == .swap || (isLimit && transaction.toCoinTicker != nil)
    }

    var body: some View {
        container
    }

    var container: some View {
        #if os(iOS)
            NavigationStack {
                content
            }
        #else
            content
                .presentationSizingFitted()
                .applySheetSize(700, 550)
        #endif
    }

    var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if showsFromToCards {
                    fromToCards
                }
                detailRows
                actionButtons
                if transaction.swapKitTrackerURL != nil {
                    swapKitTrackerButton
                }
            }
            .padding(16)
            .padding(.top, 20)
        }
        .onAppear { now = Date() }
        // Keyed on the order's status so the tick is torn down and re-evaluated
        // the moment it goes terminal, rather than running on for a closed
        // order until the sheet happens to be dismissed.
        .task(id: limitOrder?.status) { await tickExpiryWhileResting() }
        .background(ModalBackgroundView(width: .infinity))
        .presentationBackground(Theme.colors.bgSurface1)
        .presentationDragIndicator(.visible)
        .background(Theme.colors.bgSurface1)
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            #if os(macOS)
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: .xmark) {
                        dismiss()
                    }
                }
            #endif
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if showsFromToCards {
            TransactionHistoryTypePill(type: transaction.type)
                .padding(.top, 8)
        } else {
            VStack(spacing: 12) {
                TransactionHistoryTypePill(type: transaction.type)

                AsyncImageView(
                    logo: transaction.coinLogo,
                    size: CGSize(width: 48, height: 48),
                    ticker: transaction.coinTicker,
                    tokenChainLogo: transaction.coinChainLogo
                )

                Text(transaction.amountCrypto)
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)

                Text(transaction.amountFiat.formatToFiat(includeCurrencySymbol: true))
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - From/To Cards (Swap only)

    private var fromToCards: some View {
        ZStack {
            HStack(spacing: 8) {
                coinCard(
                    logo: transaction.coinLogo,
                    chainLogo: transaction.coinChainLogo,
                    ticker: transaction.coinTicker,
                    amount: transaction.amountCrypto,
                    fiat: transaction.amountFiat,
                    isFrom: true
                )

                coinCard(
                    logo: transaction.toCoinLogo ?? "",
                    chainLogo: transaction.toCoinChainLogo,
                    ticker: transaction.toCoinTicker ?? "",
                    amount: transaction.toAmountCrypto ?? "",
                    fiat: transaction.toAmountFiat ?? "",
                    isFrom: false
                )
            }

            chevronIcon
        }
    }

    private func coinCard(
        logo: String,
        chainLogo: String?,
        ticker: String,
        amount: String,
        fiat: String,
        isFrom: Bool
    ) -> some View {
        VStack(spacing: 8) {
            Text(isFrom ? "from".localized : "to".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.caption10)

            AsyncImageView(
                logo: logo,
                size: CGSize(width: 32, height: 32),
                ticker: ticker,
                tokenChainLogo: chainLogo
            )
            .padding(.bottom, 8)

            VStack(spacing: 4) {
                Text(amount)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)

                Text(fiat.formatToFiat(includeCurrencySymbol: true))
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private var chevronIcon: some View {
        Image(systemName: "chevron.right")
            .foregroundStyle(Theme.colors.textButtonDisabled)
            .font(Theme.fonts.caption12)
            .bold()
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(60)
            .padding(8)
            .background(Theme.colors.bgPrimary)
            .cornerRadius(60)
            .overlay(
                Circle()
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
    }

    // MARK: - Detail Rows

    private var detailRows: some View {
        VStack(spacing: 0) {
            statusRow

            if let failure = failureReasonText {
                Separator().opacity(0.2)
                detailRowMultiline(title: "failureReason".localized, value: failure, valueColor: Theme.colors.alertError)
            }

            limitOrderRows

            Separator().opacity(0.2)
            detailRow(title: "from".localized, value: truncatedAddress(transaction.fromAddress))
            Separator().opacity(0.2)
            detailRow(title: "to".localized, value: truncatedAddress(transaction.toAddress))
            Separator().opacity(0.2)
            detailRow(title: "date".localized, value: formattedDate)
            Separator().opacity(0.2)
            detailRow(title: "fee".localized, value: feeText)

            if let provider = transaction.swapProvider {
                Separator().opacity(0.2)
                detailRow(title: "provider".localized, value: provider)
            }

            Separator().opacity(0.2)
            detailRow(title: "network".localized, value: transaction.network)
        }
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    // MARK: - Status

    @ViewBuilder
    private var statusRow: some View {
        if isLimit {
            let display = LimitOrderStatusDisplay.make(
                uiStatus: transaction.swapTrackingUiStatus,
                details: limitOrder,
                errorMessage: transaction.errorMessage
            )
            detailRow(
                title: "status".localized,
                value: display.title,
                valueColor: TransactionHistoryCardView.limitStatusColor(display.kind)
            )
        } else {
            detailRow(title: "status".localized, value: statusText, valueColor: statusColor)
        }
    }

    /// Raw on-chain text, shown only for a genuine failure.
    ///
    /// A limit row must not use the coarse `.error` status for this: the row
    /// storage collapses refunded / expired / cancelled into `.error` too, and
    /// an expired order is not a failure with a reason to report.
    private var failureReasonText: String? {
        guard let message = transaction.errorMessage?.nilIfEmpty else { return nil }
        if isLimit {
            guard transaction.swapTrackingUiStatus == .failed else { return nil }
            return message
        }
        return transaction.status == .error ? message : nil
    }

    // MARK: - Limit Order Rows

    /// Target price + expiry, and — for a partial fill — what actually
    /// happened.
    ///
    /// The `From -> To` pair above keeps showing the original INTENT; these
    /// rows say what became of it. That separation is what lets one sheet
    /// describe every state, and it's how a two-leg settlement is expressed: an
    /// order that expired 40% filled renders `Expired` + `Filled: 40% · 0.005
    /// WBTC received` + `Refunded: 600.12 RUNE` — both outbounds, honestly.
    @ViewBuilder
    private var limitOrderRows: some View {
        if isLimit, let order = limitOrder {
            Separator().opacity(0.2)
            targetRow(order)

            if let filled = filledRowValue(order) {
                Separator().opacity(0.2)
                detailRow(title: "limitSwap.detail.filled".localized, value: filled)
            }

            if let refunded = refundedRowValue(order) {
                Separator().opacity(0.2)
                detailRow(title: "limitSwap.detail.refunded".localized, value: refunded)
            }
        }
    }

    /// `Target · 1 BTC = 15.5 ETH · [⏰ 11h 32m left]`
    private func targetRow(_ order: LimitOrderDetails) -> some View {
        HStack(spacing: 4) {
            Text("limitSwap.detail.target".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(targetPriceText(order))
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.colors.bgSurface2)
                .cornerRadius(8)

            if let expiry = expiryChipText(order) {
                HStack(spacing: 4) {
                    Image("calendar-clock")
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(expiry)
                }
                .foregroundStyle(Theme.colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.colors.bgSurface2)
                .cornerRadius(8)
            }
        }
        .font(Theme.fonts.bodySMedium)
        .padding(.vertical, 16)
    }

    /// `1 BTC = 15.5 ETH` — the price the order actually executes at, in the
    /// same terms the Verify screen showed when it was signed.
    private func targetPriceText(_ order: LimitOrderDetails) -> String {
        String(
            format: "limitSwap.detail.targetPriceFormat".localized,
            transaction.coinTicker,
            order.targetPrice.formatForDisplay(),
            transaction.toCoinTicker ?? ""
        )
        .trimmingCharacters(in: .whitespaces)
    }

    /// Time left before the order expires, or `nil` when there is no honest
    /// answer to give.
    ///
    /// Rendered ONLY from a live queue observation, and only while the order
    /// can still fill. The stored TTL + creation date could always produce a
    /// number, but it would be a guess: it assumes the deposit was queued the
    /// instant it was signed and that blocks are exactly 6s, and it keeps
    /// counting down for an order that already closed. No chip is better than a
    /// confident wrong one.
    private func expiryChipText(_ order: LimitOrderDetails) -> String? {
        guard !order.isTerminal, let expiry = order.expiry else { return nil }
        let remaining = expiry.secondsRemaining(now: now)
        guard remaining > 0 else { return nil }
        return String(
            format: "limitSwap.expiry.remainingFormat".localized,
            LimitOrderFormatting.compactDuration(remaining)
        )
    }

    /// `40% · 0.005 WBTC received`, only while a partial fill is the story.
    ///
    /// Hidden on a full fill: that's the ordinary `Successful` case and the
    /// from/to pair already tells it. Hidden at 0%: there is nothing to report.
    private func filledRowValue(_ order: LimitOrderDetails) -> String? {
        guard order.isPartiallyFilled,
              let fraction = order.fillFraction,
              let percent = LimitOrderFormatting.percent(fraction) else {
            return nil
        }
        guard let received = receivedAmountText(order) else {
            // The percentage alone is still true and worth saying.
            return percent
        }
        return String(format: "limitSwap.detail.filledValueFormat".localized, percent, received)
    }

    /// `0.005 WBTC` — what has actually been paid out in the target asset.
    private func receivedAmountText(_ order: LimitOrderDetails) -> String? {
        guard let out = order.fill.paidOutAmount, out > 0,
              let ticker = transaction.toCoinTicker?.nilIfEmpty else {
            return nil
        }
        // THORChain accounts in 1e8 fixed point for EVERY asset, regardless of
        // the asset's own decimals — so this scale is the protocol's, not the
        // coin's, and must not be read off `Coin.decimals`.
        let amount = out.toDecimal(decimals: Coin.thorchainFixedPointExponent)
        return "\(amount.formatForDisplay()) \(ticker)"
    }

    /// `600.12 RUNE` — the unfilled remainder that came back.
    ///
    /// The second leg of the settlement. Only once terminal: a live order's
    /// unfilled remainder is still resting, not refunded.
    private func refundedRowValue(_ order: LimitOrderDetails) -> String? {
        guard order.wasRefunded, let refunded = order.fill.refundedAmount, refunded > 0 else { return nil }
        let amount = refunded.toDecimal(decimals: Coin.thorchainFixedPointExponent)
        return "\(amount.formatForDisplay()) \(transaction.coinTicker)"
    }

    /// Re-publishes `now` so the expiry chip ticks down while the sheet is
    /// open. Stops as soon as the order can't fill any more — a closed order
    /// has no countdown, and this must not keep waking for one.
    private func tickExpiryWhileResting() async {
        guard isLimit else { return }
        while !Task.isCancelled {
            // Re-checked every iteration, not just on entry: an order can go
            // terminal, or run its countdown out, while the sheet sits open.
            // There is nothing left to animate then, and waking once a second
            // to re-render an unchanged chip is pure battery.
            guard let order = limitOrder, !order.isTerminal,
                  let expiry = order.expiry, !expiry.hasElapsed(now: Date()) else {
                return
            }
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            now = Date()
        }
    }

    private func detailRow(title: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor ?? Theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.colors.bgSurface2)
                .cornerRadius(8)
        }
        .font(Theme.fonts.bodySMedium)
        .padding(.vertical, 16)
    }

    private func detailRowMultiline(title: String, value: String, valueColor: Color? = nil) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor ?? Theme.colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.colors.bgSurface2)
                .cornerRadius(8)
        }
        .font(Theme.fonts.bodySMedium)
        .padding(.vertical, 16)
    }

    // MARK: - Explorer Button

    private var providerExplorerURL: URL? {
        ExplorerLinkBuilder.url(for: transaction)
    }

    /// A limit order pairs "View on Explorer" with "Copy TX Hash" — the inbound
    /// hash IS the order's identity on-chain, so it is the one thing a user
    /// needs to hand to anyone asking about their order.
    ///
    /// Slot note: "Cancel Order" belongs directly BELOW this row, full width,
    /// and is resting-only (`limitOrder?.isTerminal == false`). It is not built
    /// here — cancelling means constructing an `m=<` MsgDeposit, which is its
    /// own change. The layout leaves room for it rather than pretending: an
    /// always-visible button that does nothing would be worse than its absence.
    @ViewBuilder
    private var actionButtons: some View {
        if isLimit {
            HStack(spacing: 8) {
                explorerButton
                copyHashButton
            }
        } else {
            explorerButton
                .fixedSize()
        }
    }

    private var explorerButton: some View {
        PrimaryButton(title: "viewOnExplorer", type: .secondary) {
            if let url = providerExplorerURL {
                openURL(url)
            }
        }
    }

    private var copyHashButton: some View {
        PrimaryButton(title: "limitSwap.detail.copyTxHash", type: .secondary) {
            ClipboardManager.copyToClipboard(transaction.txHash)
        }
    }

    private var swapKitTrackerButton: some View {
        PrimaryButton(title: "swapKitViewOnTracker", type: .secondary) {
            if let url = transaction.swapKitTrackerURL {
                openURL(url)
            }
        }
        .fixedSize()
    }

    // MARK: - Helpers

    private var statusText: String {
        switch transaction.status {
        case .successful:
            return "successful".localized
        case .error:
            return "error".localized
        case .inProgress:
            return "inProgress".localized
        }
    }

    private var statusColor: Color {
        switch transaction.status {
        case .successful:
            return Theme.colors.alertSuccess
        case .error:
            return Theme.colors.alertError
        case .inProgress:
            return Theme.colors.textTertiary
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: transaction.createdAt)
    }

    private var feeText: String {
        if transaction.feeCrypto.isEmpty {
            return "-"
        }
        return transaction.feeCrypto
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }

}
