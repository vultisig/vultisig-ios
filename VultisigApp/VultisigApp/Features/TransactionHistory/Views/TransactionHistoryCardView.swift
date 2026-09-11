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

    /// Whether the collapsed row shows the completed-swap layout (two amount
    /// legs + a `FROM → TO` pill) instead of today's single fiat/crypto
    /// amount. See the static twin below for the routing rule.
    private var showsSwapLegs: Bool {
        Self.showsSwapLegs(
            type: transaction.type,
            toAmountCrypto: transaction.toAmountCrypto,
            toCoinTicker: transaction.toCoinTicker
        )
    }

    /// Whether the "via {provider}" badge belongs on this row. See the
    /// static twin below for the routing rule.
    private var showsViaBadge: Bool {
        Self.showsViaBadge(
            hasProvider: transaction.swapProvider != nil,
            isExpanded: isExpanded,
            showsSwapLegs: showsSwapLegs
        )
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
        .padding(.bottom, showsViaBadge ? 20 : 0)
        .cornerRadius(Theme.radius.xl)
        .background(
            Theme.radius.xl.shape
                .inset(by: 1)
                .fill(Theme.colors.bgSurface1)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if showsViaBadge {
                viaBadge
            }
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

    // MARK: - Completed Swap/Limit Legs Routing

    /// Whether this row shows the completed-swap layout: two amount legs
    /// (`+to` / `-from`) plus a `FROM → TO` pill, replacing today's single
    /// fiat/crypto amount. Requires the to-side to actually be known — a
    /// limit order placed from a native source (`recordLimitOrder`) never
    /// resolves `toCoinTicker`/`toAmountCrypto` (the co-signer only sees the
    /// `=<` memo, never a real `Coin`), so that row keeps the old layout
    /// rather than claiming a pair it cannot show.
    static func showsSwapLegs(
        type: TransactionHistoryType,
        toAmountCrypto: String?,
        toCoinTicker: String?
    ) -> Bool {
        guard type == .swap || type == .limit else { return false }
        guard let toAmountCrypto, !toAmountCrypto.isEmpty else { return false }
        guard let toCoinTicker, !toCoinTicker.isEmpty else { return false }
        return true
    }

    /// Whether the "via {provider}" badge belongs on this row.
    ///
    /// Gone only on a COMPLETED row already showing the swap legs — the
    /// `FROM → TO` pill takes over naming the route there. Every other
    /// swap-provider row keeps it: an in-progress row's `expandedContent`
    /// names both coins but not the provider, and a to-side-less limit
    /// order still needs the badge to say what it routed through.
    static func showsViaBadge(hasProvider: Bool, isExpanded: Bool, showsSwapLegs: Bool) -> Bool {
        guard hasProvider else { return false }
        return isExpanded || !showsSwapLegs
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
            if showsSwapLegs {
                swapPairIcon
            } else {
                coinIcon
            }

            if transaction.type == .trustLineActivation {
                trustLineColumn
            } else if showsSwapLegs {
                swapLegsColumn
            } else {
                amountColumn
            }

            Spacer()

            if transaction.type == .send {
                addressPill
            } else if showsSwapLegs {
                swapPairPill
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

    /// A completed swap/limit row's icon: the FROM token's left half against
    /// the TO token's right half, meeting as one 24pt circle split down the
    /// middle — so the row names both assets before the eye reaches the
    /// amounts. Send/receive rows keep the single `coinIcon` above.
    private var swapPairIcon: some View {
        HStack(spacing: 0) {
            iconHalf(
                logo: transaction.coinLogo,
                ticker: transaction.coinTicker,
                keeping: .leading
            )
            iconHalf(
                logo: transaction.toCoinLogo ?? "",
                ticker: transaction.toCoinTicker ?? "",
                keeping: .trailing
            )
        }
        .frame(width: 24, height: 24)
    }

    /// One half of `swapPairIcon`. The logo renders at its FULL 24pt inside a
    /// 12pt-wide clip, so it keeps its own circular mask and true proportions
    /// rather than being squashed to half width; `keeping` selects which side
    /// survives the clip.
    ///
    /// No chain badge here: at 12pt it would be sliced down the middle, and
    /// the `FROM → TO` pill already names both assets.
    private func iconHalf(logo: String, ticker: String, keeping: Alignment) -> some View {
        AsyncImageView(
            logo: logo,
            size: CGSize(width: 24, height: 24),
            ticker: ticker,
            tokenChainLogo: nil
        )
        .frame(width: 12, height: 24, alignment: keeping)
        .clipped()
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

    /// The completed row's two legs: `+{toAmount} {toTicker}` in primary
    /// above `-{fromAmount} {fromTicker}` in tertiary, same size
    /// (`priceFootnote`) — confirmed against the Figma frame, which uses one
    /// size for both lines and only the colour to demote the from-side.
    ///
    /// Rebuilds the ticker from `toCoinTicker`/`coinTicker` via
    /// `Self.stripTicker` rather than trusting `toAmountCrypto`/
    /// `amountCrypto` to already carry it: the `SwapDoneScreen` path
    /// pre-formats `"\(amount) \(ticker)"`, but the co-signer's
    /// `TransactionHistoryRecorder.recordFromKeysignPayload` records
    /// `toAmountCrypto` as a bare number — the exact reason
    /// `cryptoAmountText` strips defensively instead of assuming the ticker
    /// is there.
    ///
    /// ⚠️ `toAmountCrypto` is the quote's EXPECTED output, frozen when the
    /// row was recorded and never refreshed with what actually landed
    /// (`TransactionHistoryViewModel.updateStatus`,
    /// `SwapKitTrackingService.applyResponseToTx` both carry it forward
    /// verbatim). The in-progress row labels the same value "expectedPayout"
    /// for exactly this reason; this completed row has no such label and
    /// reads as fact — a known, accepted property of the data.
    private var swapLegsColumn: some View {
        let toTicker = transaction.toCoinTicker ?? ""
        let toAmount = Self.stripTicker(from: transaction.toAmountCrypto ?? "", ticker: toTicker)
        let fromAmount = Self.stripTicker(from: transaction.amountCrypto, ticker: transaction.coinTicker)

        return VStack(alignment: .leading, spacing: 2) {
            Text("+\(toAmount) \(toTicker)")
                .foregroundStyle(Theme.colors.textPrimary)
            Text("-\(fromAmount) \(transaction.coinTicker)")
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .font(Theme.fonts.priceFootnote)
        .lineLimit(1)
    }

    /// `FROM → TO`, in the same pill geometry `addressPill` uses for a send
    /// row's `to 0x…` — the slot a completed swap/limit row fills instead.
    private var swapPairPill: some View {
        Text("\(transaction.coinTicker) → \(transaction.toCoinTicker ?? "")")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textPrimary)
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
        let amount = Self.stripTicker(from: crypto, ticker: ticker)

        return HStack(spacing: 4) {
            Text(amount)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(ticker)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .font(Theme.fonts.priceFootnote)
        .lineLimit(1)
    }

    /// Bare numeric amount from a pre-formatted `"{amount} {ticker}"` string
    /// that may or may not actually carry the suffix — not every recorder
    /// path appends one (see `swapLegsColumn`). A no-op when the ticker
    /// isn't present, so callers can always safely re-append it themselves.
    static func stripTicker(from crypto: String, ticker: String) -> String {
        // Matches the SPACE-delimited suffix, not a bare `hasSuffix(ticker)`
        // — a custom token can carry a numeric-looking ticker (e.g. "50"),
        // which would otherwise chew digits off an amount like "200.50"
        // that merely ends in the same characters.
        let suffix = " \(ticker)"
        return crypto.hasSuffix(suffix) ? String(crypto.dropLast(suffix.count)) : crypto
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}
