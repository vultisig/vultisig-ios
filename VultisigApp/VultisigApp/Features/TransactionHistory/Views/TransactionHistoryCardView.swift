//
//  TransactionHistoryCardView.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryCardView: View {
    let transaction: TransactionHistoryData
    /// The order behind this row, for `.limit` rows whose order record is on
    /// this device. `nil` for every other type — and for a limit row on a
    /// co-signer, which never persists a `LimitOrder`. Only supplies fill
    /// progress; the status resolves without it.
    var limitOrder: LimitOrderDetails?

    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    private var isExpanded: Bool {
        Self.shouldExpand(status: transaction.status, type: transaction.type)
            && (transaction.type != .limit || transaction.toCoinTicker != nil)
    }

    private var failureReasonText: String? {
        TransactionHistoryFailureReasonPresentation.displayText(for: transaction.errorMessage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topRow

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .padding(16)
        .padding(.bottom, transaction.swapProvider != nil ? 20 : 0)
        .cornerRadius(Theme.radius.xl)
        .background(
            Theme.radius.xl.shape
                .inset(by: 1)
                .fill(Theme.colors.bgSurface1)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            viaBadge
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        .onAppear {
            // No timer for limit rows — they don't render the elapsed chip, so
            // ticking once a second for an order that rests for days would be
            // pure wakeups for a label nothing shows.
            if transaction.status == .inProgress && transaction.type != .limit { startTimer() }
        }
        .onDisappear { stopTimer() }
        .onChange(of: transaction.status) { _, newStatus in
            if newStatus != .inProgress {
                stopTimer()
            }
        }
    }

    /// The expanded layout is a `from -> to` transfer diagram: an amount at the
    /// top, an arrow, a recipient at the bottom. Only types that MOVED something
    /// earn it — an approve grants an allowance, and a trust-line activation
    /// opens a line and locks a reserve. Neither has an amount or a recipient to
    /// put in those slots.
    static func shouldExpand(status: TransactionHistoryStatus, type: TransactionHistoryType) -> Bool {
        status == .inProgress && type != .approve && type != .trustLineActivation
    }

    // MARK: - Top Row

    private var topRow: some View {
        HStack {
            TransactionHistoryTypePill(type: transaction.type)

            Spacer()

            if transaction.type == .limit {
                if isLimitTerminal {
                    // Closed: the two-line status line carries the outcome and
                    // its colour (filled / closed-unfilled / failed), plus any
                    // partial-fill progress.
                    limitStatusView
                } else {
                    // Live: a pill WITHOUT the elapsed timer. The timer counts up
                    // from broadcast — meaningful for a swap due to land in
                    // seconds, absurd for an order that rests for 12-72h
                    // ("In progress... 1440m 12s"). A cancel in flight reads
                    // "Cancelling…" so the state the user just triggered is
                    // visible on the list, not only on the detail sheet; a plain
                    // resting order reads "In progress".
                    limitInProgressChip
                }
            } else if transaction.status == .inProgress {
                inProgressChip
            } else {
                statusView
            }
        }
    }

    // MARK: - Limit Order Status

    /// Whether this limit order has closed. Reads the authoritative order when we
    /// hold it — the same source the Cancel button and the status label read, so
    /// they cannot disagree — and falls back to the row's mirror for a co-signer,
    /// which never persists a `LimitOrder`.
    private var isLimitTerminal: Bool {
        Self.isLimitTerminal(limitOrder: limitOrder, uiStatus: transaction.swapTrackingUiStatus)
    }

    /// Pure so the routing can be pinned by tests. Resolves through the SAME
    /// effective-status resolver the detail sheet and status label use, so the
    /// pill routing here cannot disagree with them about whether an order is
    /// live — including the `.failed` exception. The authoritative order wins over
    /// the row it mirrors: a resting order that is `.cancelling` is still live and
    /// shows the in-progress pill the instant the order says so, not a poll later.
    static func isLimitTerminal(limitOrder: LimitOrderDetails?, uiStatus: SwapTrackingUiStatus) -> Bool {
        LimitOrderStatusDisplay.effectiveUiStatus(uiStatus: uiStatus, details: limitOrder).isTerminal
    }

    /// Whether a live limit order has a cancel in flight. Reads the SAME
    /// effective status the routing and the detail sheet use, so the pill can't
    /// say "In progress" while the button and the sheet say "Cancelling".
    private var isLimitCancelling: Bool {
        LimitOrderStatusDisplay.effectiveUiStatus(
            uiStatus: transaction.swapTrackingUiStatus,
            details: limitOrder
        ) == .cancelling
    }

    /// The pill for a LIVE limit order: the shared `inProgressChip`'s styling
    /// without its elapsed timer. Reads "Cancelling…" once a cancel is in flight
    /// (the state persists on the order the instant it broadcasts), otherwise
    /// "In progress". See the routing in `topRow` for why the timer is dropped.
    private var limitInProgressChip: some View {
        Text((isLimitCancelling ? "limitSwap.status.cancelling" : "inProgress").localized)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.colors.bgPrimary)
            .cornerRadius(Theme.radius.pill)
    }

    /// Two-line status: the state, and beneath it the progress.
    ///
    /// This is the mock's existing two-line status slot (used there for an
    /// error message), reused verbatim — a partially-filled order is still
    /// in progress, so its percentage is a qualifier on the status line rather
    /// than a new component. Shown only once the order is TERMINAL — a live
    /// order shows the pill above.
    @ViewBuilder
    private var limitStatusView: some View {
        let display = LimitOrderStatusDisplay.make(
            uiStatus: transaction.swapTrackingUiStatus,
            details: limitOrder,
            errorMessage: failureReasonText
        )

        VStack(alignment: .trailing, spacing: 4) {
            Text(display.title)
            if let detail = display.detail {
                Text(detail)
            }
        }
        .font(Theme.fonts.caption12)
        .foregroundStyle(Self.limitStatusColor(display.kind))
        .multilineTextAlignment(.trailing)
    }

    /// Amber, not red, for a terminal order that didn't fill.
    ///
    /// An expired or refunded order is a NORMAL outcome — the order did exactly
    /// what it was told to and the funds came back — so painting it in the same
    /// red as a genuine failure would cry wolf on the expected case. Red is
    /// kept for an actual failure. In-progress stays tertiary, matching every
    /// other card in tx history, so "live" can never be mistaken at a glance
    /// for the green of "filled".
    static func limitStatusColor(_ kind: LimitOrderStatusDisplay.Kind) -> Color {
        switch kind {
        case .inProgress, .cancelling:
            // `.cancelling` shares the in-progress tint deliberately. It is a
            // live order with a request in flight; any colour that reads as an
            // outcome — the success green, or the amber of a closed order —
            // would announce a result nothing has observed.
            return Theme.colors.textTertiary
        case .successful:
            return Theme.colors.alertSuccess
        case .closedUnfilled:
            return Theme.colors.alertWarning
        case .failed:
            return Theme.colors.alertError
        }
    }

    // MARK: - In-Progress Chip

    private var inProgressChip: some View {
        HStack(spacing: 0) {
            Text("inProgress".localized + "... ")
                .foregroundStyle(Theme.colors.textTertiary)
            Text(elapsedTimeString)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .font(Theme.fonts.caption12)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.colors.bgPrimary)
        .cornerRadius(Theme.radius.pill)
    }

    // MARK: - Completed Status

    @ViewBuilder
    private var statusView: some View {
        Group {
            switch transaction.status {
            case .successful:
                Text("successful".localized)
                    .foregroundStyle(Theme.colors.alertSuccess)
            case .error:
                VStack(alignment: .trailing, spacing: 4) {
                    Text("error".localized)
                    if let errorMessage = failureReasonText {
                        Text(errorMessage)
                    }
                }
                .foregroundStyle(Theme.colors.alertError)
            case .inProgress:
                Text("inProgress".localized)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }.font(Theme.fonts.caption12)
    }

    // MARK: - Expanded Content (In-Progress)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            fromRow
            verticalConnector
            toRow
        }
    }

    private var fromRow: some View {
        HStack(spacing: 12) {
            AsyncImageView(
                logo: transaction.coinLogo,
                size: CGSize(width: 24, height: 24),
                ticker: transaction.coinTicker,
                tokenChainLogo: transaction.coinChainLogo
            )

            cryptoAmountText(transaction.amountCrypto, ticker: transaction.coinTicker)
        }
    }

    // MARK: - Vertical Connector

    private var verticalConnector: some View {
        HStack(spacing: 12) {
            // Vertical line centered under the 24pt icon
            ZStack {
                Theme.colors.border
                    .frame(width: 1)

                ZStack {
                    Circle()
                        .fill(Theme.colors.bgSurface1)
                        .overlay(
                            Circle()
                                .stroke(Theme.colors.border, lineWidth: 1)
                        )
                        .frame(width: 25, height: 25)

                    CircularProgressIndicator(
                        size: 24,
                        lineWidth: 1.5,
                        tint: Theme.colors.primaryAccent4
                    )

                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.colors.primaryAccent4)
                }
            }
            .frame(width: 24)

            HStack(spacing: 12) {
                Text("to".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)

                separatorLine
            }
        }
        .frame(height: 48)
    }

    private var separatorLine: some View {
        Theme.colors.border
            .frame(height: 1)
    }

    // MARK: - To Row

    @ViewBuilder
    private var toRow: some View {
        // A limit order shows the same from -> to pair as a swap; only the
        // to-side caption differs, since the order's LIM *is* a guaranteed
        // minimum output while a market swap's recorded amount is not.
        if transaction.type == .swap || transaction.type == .limit {
            swapToRow
        } else {
            sendToRow
        }
    }

    private var swapToRow: some View {
        HStack(spacing: 12) {
            if let toCoinLogo = transaction.toCoinLogo {
                AsyncImageView(
                    logo: toCoinLogo,
                    size: CGSize(width: 24, height: 24),
                    ticker: transaction.toCoinTicker ?? "",
                    tokenChainLogo: transaction.toCoinChainLogo
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                // A market swap persists the quote's EXPECTED output, so it can
                // only be labelled that. Only a limit order's recorded amount is
                // a guaranteed minimum.
                Text((transaction.type == .limit ? "minPayout" : "expectedPayout").localized)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)

                cryptoAmountText(transaction.toAmountCrypto ?? "", ticker: transaction.toCoinTicker ?? "")
            }
        }
    }

    private var sendToRow: some View {
        HStack(spacing: 12) {
            Image("vault")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(Theme.colors.textTertiary)

            Text(truncatedAddress(transaction.toAddress))
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Via Badge

    @ViewBuilder
    private var viaBadge: some View {
        if let provider = transaction.swapProvider {
            HStack(spacing: 8) {
                // The badge is "via {provider}", so its icon is the swapper's
                // brand logo — like the route/details screen — not the source
                // coin. Falls back to the raw provider name (monogram via
                // `ticker`) when the provider has no bundled brand asset.
                AsyncImageView(
                    logo: transaction.swapProviderLogo ?? provider,
                    size: CGSize(width: 16, height: 16),
                    ticker: provider,
                    tokenChainLogo: nil
                )

                HStack(spacing: 4) {
                    Text("via".localized)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Text(provider)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                .font(Theme.fonts.caption10)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .background(Theme.colors.bgSurface2)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.radius.md.points,
                    bottomLeadingRadius: 0,
                    // The badge is overlaid on the card's bottom-trailing
                    // corner, so this radius is not the badge's own geometry —
                    // it traces the card's. It has to read from the same token
                    // the card does or the badge stops following the contour it
                    // is sitting in.
                    bottomTrailingRadius: Theme.radius.xl.points,
                    topTrailingRadius: 0,
                    style: Theme.radius.xl.style
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.radius.md.points,
                    bottomLeadingRadius: 0,
                    // The badge is overlaid on the card's bottom-trailing
                    // corner, so this radius is not the badge's own geometry —
                    // it traces the card's. It has to read from the same token
                    // the card does or the badge stops following the contour it
                    // is sitting in.
                    bottomTrailingRadius: Theme.radius.xl.points,
                    topTrailingRadius: 0,
                    style: Theme.radius.xl.style
                )
                .stroke(Theme.colors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Collapsed Content (Completed)

    private var collapsedContent: some View {
        HStack(spacing: 12) {
            coinIcon

            if transaction.type == .trustLineActivation {
                trustLineColumn
            } else {
                amountColumn
            }

            Spacer()

            if transaction.type == .send {
                addressPill
            }
        }
    }

    /// What a trust-line activation says instead of an amount.
    ///
    /// The same sentence the done screen showed when the line was opened, over
    /// the issuer that identifies WHICH line — deliberately the hero's two
    /// lines, so history and the receipt tell one story. The amount column is
    /// bypassed rather than fed an empty string: a TrustSet's only number is the
    /// line's limit, and there is no honest way to render that here.
    private var trustLineColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RippleTrustSetPresentation.activationTitle(ticker: transaction.coinTicker))
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)

            Text(truncatedAddress(transaction.toAddress))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
        }
    }

    private var coinIcon: some View {
        AsyncImageView(
            logo: transaction.coinLogo,
            size: CGSize(width: 24, height: 24),
            ticker: transaction.coinTicker,
            tokenChainLogo: transaction.coinChainLogo
        )
    }

    private var amountColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(transaction.amountFiat.formatToFiat(includeCurrencySymbol: true))
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)

            cryptoAmountText(transaction.amountCrypto, ticker: transaction.coinTicker)
        }
    }

    private var addressPill: some View {
        let prefix = transaction.type == .send ? "to".localized : "from".localized

        return HStack(spacing: 4) {
            Text(prefix)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(truncatedAddress(transaction.toAddress))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(Theme.radius.pill)
        .overlay(
            Theme.radius.pill.shape
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    // MARK: - Timer

    private var elapsedTimeString: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return "\(minutes)m \(seconds)s"
    }

    private func startTimer() {
        elapsedTime = Date().timeIntervalSince(transaction.createdAt)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(transaction.createdAt)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    private func cryptoAmountText(_ crypto: String, ticker: String) -> some View {
        let amount = crypto.hasSuffix(ticker)
            ? String(crypto.dropLast(ticker.count)).trimmingCharacters(in: .whitespaces)
            : crypto

        return HStack(spacing: 4) {
            Text(amount)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(ticker)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .font(Theme.fonts.priceFootnote)
        .lineLimit(1)
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}
