//
//  SwapReworkQuoteViews.swift
//  VultisigApp
//
//  The quote under the amounts: one route card (provider, tag, time, total
//  fees, countdown), the fee breakdown it expands into, the approval note and
//  the inline issue card for whatever blocks the swap.
//

import SwiftUI

struct SwapReworkRouteCard: View {
    let route: SwapReworkRouteSummary
    let timer: SwapReworkQuoteTimer
    let fees: SwapReworkFeeRows?
    let onTap: () -> Void
    let onTapFees: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            providerRow
            if let fees {
                Separator(color: Theme.colors.borderLight, opacity: 1)
                    .padding(.horizontal, 16)
                SwapReworkTierLine(fees: fees, action: onTapFees)
            }
        }
        .swapReworkCard(highlighted: false)
    }

    private var providerRow: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                SwapReworkProviderLogo(name: route.providerName, logo: route.providerLogo, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(route.providerName)
                            .font(Theme.fonts.bodyMMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let tag = route.tag {
                            SwapReworkRouteTagView(tag: tag)
                        }
                    }
                    Text(detailText)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                SwapReworkCountdown(timer: timer)
                if route.isSelectable {
                    Image(systemName: "chevron.right")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapReworkRouteCard")
    }

    private var detailText: String {
        let parts = [route.etaText, route.feesText.isEmpty ? "" : String(format: "swapReworkFeesShort".localized, route.feesText)]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// "Vultisig fee 0.30% ~~0.50%~~   Gold · 40% off": the tier discount where the
/// eye already is. Taps open the full breakdown.
struct SwapReworkTierLine: View {
    let fees: SwapReworkFeeRows
    let action: () -> Void

    private var breakdown: SwapFeeBreakdown { fees.breakdown }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("swapReworkVultisigFeeLabel".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(breakdown.input.vultisigIncludedInRate ? "swap.included_in_rate".localized : breakdown.chargedRateText)
                    .font(Theme.fonts.priceCaption)
                    .foregroundStyle(Theme.colors.textPrimary)
                if breakdown.percentOff > 0 && !breakdown.input.vultisigIncludedInRate {
                    Text(breakdown.listRateText)
                        .font(Theme.fonts.priceCaption)
                        .strikethrough()
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer(minLength: 4)
                if let tier = fees.tierName, breakdown.percentOff > 0 {
                    Text(String(format: "swapReworkTierBadge".localized, tier, breakdown.percentOff))
                        .font(Theme.fonts.caption10)
                        .foregroundStyle(Theme.colors.alertWarning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.colors.alertWarning.opacity(0.16))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "chevron.down")
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapReworkTierLine")
    }
}

struct SwapReworkRouteTagView: View {
    let tag: SwapRouteTag

    var body: some View {
        Text(title)
            .font(Theme.fonts.caption10)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    private var title: String {
        switch tag {
        case .bestReturn: return "swapReworkBestReturn".localized
        case .fastest: return "swapReworkFastest".localized
        }
    }

    private var color: Color {
        switch tag {
        case .bestReturn: return Theme.colors.alertSuccess
        case .fastest: return Theme.colors.primaryAccent4
        }
    }
}

struct SwapReworkCountdown: View {
    let timer: SwapReworkQuoteTimer

    var body: some View {
        HStack(spacing: 6) {
            ring
            Text(label)
                .font(Theme.fonts.priceCaption)
                .monospacedDigit()
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("swapReworkCountdown")
    }

    @ViewBuilder
    private var ring: some View {
        switch timer.state {
        case .refreshing:
            ProgressView()
                .controlSize(.mini)
                .tint(Theme.colors.primaryAccent4)
                .frame(width: 16, height: 16)
        default:
            ZStack {
                Circle().stroke(Theme.colors.bgSurface2, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: timer.fraction)
                    .stroke(Theme.colors.primaryAccent4, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.fraction)
            }
            .frame(width: 16, height: 16)
        }
    }

    private var label: String {
        switch timer.state {
        case .idle, .refreshing: return ""
        case .live(let seconds): return SwapQuoteClock.countdownText(seconds: seconds)
        case .expired: return SwapQuoteClock.countdownText(seconds: 0)
        }
    }
}

struct SwapReworkProviderLogo: View {
    let name: String
    let logo: String?
    let size: CGFloat

    var body: some View {
        // Same loader as the existing route rows: bundled brand art, or a
        // monogram for providers that ship none.
        AsyncImageView(logo: logo ?? "", size: CGSize(width: size, height: size), ticker: name, tokenChainLogo: nil)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Fees

struct SwapReworkFeeCard: View {
    let fees: SwapReworkFeeRows
    let isExpanded: Bool
    let onToggle: () -> Void

    private var breakdown: SwapFeeBreakdown { fees.breakdown }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text("swapReworkFees".localized)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Spacer()
                    Text(breakdown.displayTotalFiat.formatToFiat())
                        .font(Theme.fonts.priceBodyL)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("swapReworkFeesToggle")

            if isExpanded {
                Separator(color: Theme.colors.borderLight, opacity: 1)
                VStack(alignment: .leading, spacing: 12) {
                    row(fees.networkLabel, value: breakdown.input.networkFiat.formatToFiat(), detail: fees.networkCrypto)
                    if let approvalLabel = fees.approvalLabel {
                        row(approvalLabel, value: breakdown.input.approvalFiat.formatToFiat())
                    }
                    if let protocolLabel = fees.protocolLabel {
                        row(protocolLabel, value: breakdown.input.protocolFiat.formatToFiat())
                    }
                    vultisigRow
                    Separator(color: Theme.colors.borderLight, opacity: 1)
                    if !fees.minimumReceived.isEmpty {
                        row("swapReworkMinimumReceived".localized, value: fees.minimumReceived)
                    }
                    row("swapReworkMaxSlippage".localized, value: fees.slippageText)
                    if !fees.priceImpactText.isEmpty {
                        row("swapReworkPriceImpact".localized, value: fees.priceImpactText)
                    }
                    Separator(color: Theme.colors.borderLight, opacity: 1)
                    row("swapReworkLeavesVault".localized, value: fees.leavesVaultText)
                }
                .padding(16)
                .transition(.opacity)
            }
        }
        .swapReworkCard(highlighted: false)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    @ViewBuilder
    private var vultisigRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "swapReworkVultisigFee".localized, breakdown.chargedRateText))
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                Spacer(minLength: 8)
                if breakdown.input.vultisigIncludedInRate {
                    Text("swap.included_in_rate".localized)
                        .font(Theme.fonts.bodySRegular)
                        .foregroundStyle(Theme.colors.textSecondary)
                } else {
                    if breakdown.showsStrikethrough {
                        Text(breakdown.input.vultisigListFiat.formatToFiat())
                            .font(Theme.fonts.priceFootnote)
                            .strikethrough()
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                    Text(breakdown.input.vultisigNetFiat.formatToFiat())
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
            }
            if let tier = fees.tierName, breakdown.tierSavingsFiat > 0 {
                Text(String(format: "swapReworkTierSaves".localized, tier, breakdown.percentOff, breakdown.tierSavingsFiat.formatToFiat()))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.alertWarning)
            } else if fees.tierName == nil && !breakdown.isWaivedByQuote {
                Text(String(format: "swapReworkNoTier".localized, breakdown.listRateText))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }

    private func row(_ title: String, value: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text(value)
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                if let detail {
                    Text("· " + detail)
                        .font(Theme.fonts.priceFootnote)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Approval

struct SwapReworkApprovalCard: View {
    let approval: SwapReworkApproval

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.primaryAccent4)
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(bodyText)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .swapReworkCard(highlighted: false)
        .accessibilityIdentifier("swapReworkApprovalCard")
    }

    private var titleText: String {
        switch approval.legs {
        case 2?: return "swapReworkApprovalTitleReset".localized
        case 1?: return "swapReworkApprovalTitleNeeded".localized
        default: return "swapReworkApprovalTitle".localized
        }
    }

    private var bodyText: String {
        switch approval.legs {
        case 2?: return String(format: "swapReworkApprovalBodyReset".localized, approval.ticker, approval.spenderName)
        case 1?: return String(format: "swapReworkApprovalBodyNeeded".localized, approval.amountText, approval.ticker, approval.spenderName)
        default: return String(format: "swapReworkApprovalBody".localized, approval.amountText, approval.ticker, approval.spenderName)
        }
    }
}

// MARK: - Issues

struct SwapReworkIssueCard: View {
    let issue: SwapReworkIssue
    let pair: (pay: String, receive: String)
    let gasDetail: String?
    var minimumText: String?
    /// "Add ETH": opens the add-gas sheet from the not-enough-gas card.
    var gasActionTitle: String?
    var onGasAction: (() -> Void)?

    var body: some View {
        VStack(alignment: issue == .noRoute ? .center : .leading, spacing: 8) {
            if issue == .noRoute {
                Image(systemName: "arrow.triangle.branch")
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            HStack(alignment: .top, spacing: 10) {
                if issue != .noRoute {
                    Image(systemName: icon)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(tint)
                }
                VStack(alignment: issue == .noRoute ? .center : .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(issue == .noRoute ? Theme.colors.textPrimary : tint)
                    if let message {
                        Text(message)
                            .font(Theme.fonts.bodySRegular)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .multilineTextAlignment(issue == .noRoute ? .center : .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if issue != .noRoute { Spacer(minLength: 0) }
            }
            if issue == .notEnoughGas, let gasActionTitle, let onGasAction {
                Button(action: onGasAction) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text(gasActionTitle)
                    }
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Theme.colors.bgSurface2)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 30)
                .accessibilityIdentifier("swapReworkAddGas")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(tint.opacity(issue == .noRoute ? 0 : 0.10))
        .swapReworkCard(highlighted: false)
        .overlay(Theme.radius.lg.shape.stroke(tint.opacity(issue == .noRoute ? 0 : 0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("swapReworkIssue")
    }

    private var tint: Color {
        switch issue {
        case .overBalance, .notEnoughGas, .other: return Theme.colors.alertError
        case .priceMoved, .tradingHalted, .amountTooSmall: return Theme.colors.alertWarning
        case .quoteExpired, .noRoute: return Theme.colors.textSecondary
        }
    }

    private var icon: String {
        switch issue {
        case .notEnoughGas: return "fuelpump"
        case .quoteExpired: return "clock"
        case .overBalance, .other: return "exclamationmark.circle"
        default: return "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch issue {
        case .overBalance: return String(format: "swapReworkIssueOverBalance".localized, pair.pay)
        case .notEnoughGas: return "swapReworkIssueGasTitle".localized
        case .amountTooSmall: return "swapReworkIssueTooSmall".localized
        case .tradingHalted(let provider): return String(format: "swapReworkIssueHalted".localized, provider, pair.receive)
        case .noRoute: return String(format: "swapReworkIssueNoRoute".localized, pair.pay, pair.receive)
        case .priceMoved(let move): return String(format: "swapReworkIssuePriceMoved".localized, move.changeText)
        case .quoteExpired: return "swapReworkIssueExpired".localized
        case .other(let title, _): return title
        }
    }

    private var message: String? {
        switch issue {
        case .overBalance: return "swapReworkIssueOverBalanceBody".localized
        case .notEnoughGas: return gasDetail
        case .amountTooSmall:
            return minimumText.map { String(format: "swapReworkIssueTooSmallMinimum".localized, $0) }
                ?? "swapReworkIssueTooSmallBody".localized
        case .tradingHalted: return "swapReworkIssueHaltedBody".localized
        case .noRoute: return "swapReworkIssueNoRouteBody".localized
        case .priceMoved: return "swapReworkIssuePriceMovedBody".localized
        case .quoteExpired: return "swapReworkIssueExpiredBody".localized
        case .other(_, let message): return message
        }
    }
}

/// R4's fees-over-5% card: how much of the swap goes to fees, a gas vs
/// Vultisig share bar, and what the share would be at ten times the amount
/// (gas is fixed, so it shrinks). Review stays enabled.
struct SwapReworkFeeWarningCard: View {
    let warning: SwapReworkFeeWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.colors.alertWarning)
                Text(String(format: "swapReworkFeeShareTitle".localized, warning.shareText))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.alertWarning)
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule().fill(Theme.colors.alertWarning)
                        .frame(width: max(4, proxy.size.width * warning.gasPart))
                    Capsule().fill(Theme.colors.alertError.opacity(0.8))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                legend(color: Theme.colors.alertWarning, text: "\(warning.gasLabel) \(warning.gasText)")
                legend(color: Theme.colors.alertError.opacity(0.8), text: String(format: "swapReworkFeeOther".localized, warning.vultisigText))
                Spacer(minLength: 4)
                Text(String(format: "swapReworkYouGet".localized, warning.receiveText))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            if let atScale = warning.atScaleText {
                Text(atScale)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Theme.colors.alertWarning.opacity(0.10))
        .swapReworkCard(highlighted: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("swapReworkFeeWarning")
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }
}

/// Fees and price impact take a large share of the value. A warning, not a
/// block: the numbers above are honest, this makes sure they are read.
struct SwapReworkValueLossCard: View {
    let lossText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.alertWarning)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "swapReworkValueLossTitle".localized, lossText))
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.alertWarning)
                Text("swapReworkValueLossBody".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.colors.alertWarning.opacity(0.10))
        .swapReworkCard(highlighted: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("swapReworkValueLoss")
    }
}

// MARK: - Route sheet

/// R4 route sheet: Best return / Fastest tabs, each row with its all-in fees
/// (route fees plus gas), the best row marked "Most to your vault" and every
/// other row its gap to the best in destination units and fiat.
struct SwapReworkRouteSheet: View {
    let routes: [SwapRankedRoute]
    let selectedID: String?
    let receiveTicker: String
    let receiveIsBitcoin: Bool
    let timer: SwapReworkQuoteTimer
    /// "Ethereum gas $0.84", shared by every route; nil when not known.
    let gasNote: String?
    let onSelect: (String) -> Void

    @State private var sort: SwapRouteSort = .bestReturn

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("swapReworkRoutes".localized)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                SwapReworkCountdown(timer: timer)
            }
            sortTabs
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(SwapRouteRanking.sorted(routes, by: sort)) { route in
                        routeRow(route)
                    }
                }
            }
            Text(footer)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var footer: String {
        guard let gasNote else { return "swapReworkRoutesFooter".localized }
        return String(format: "swapReworkRoutesFooterGas".localized, gasNote)
    }

    private var sortTabs: some View {
        HStack(spacing: 4) {
            ForEach(SwapRouteSort.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { sort = option }
                } label: {
                    Text(option == .bestReturn ? "swapReworkBestReturn".localized : "swapReworkFastest".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(sort == option ? Theme.colors.textPrimary : Theme.colors.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(sort == option ? Theme.colors.bgSurface2 : .clear)
                        .clipShape(Theme.radius.md.shape)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("swapReworkRouteSort-\(option.rawValue)")
            }
        }
        .padding(4)
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.lg.shape)
    }

    private func routeRow(_ route: SwapRankedRoute) -> some View {
        let selected = route.id == selectedID
        return Button { onSelect(route.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SwapReworkProviderLogo(name: route.option.providerName, logo: route.option.providerLogo, size: 28)
                    Text(route.option.providerName)
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    ForEach(route.tags, id: \.self) { tag in
                        SwapReworkRouteTagView(tag: tag)
                    }
                    Spacer(minLength: 4)
                    Text(SwapReworkFormat.amount(route.option.receivedAmount, ticker: receiveTicker))
                        .font(Theme.fonts.priceBodyS)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(detail(route))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Text(gap(route))
                        .font(Theme.fonts.priceCaption)
                        .foregroundStyle(route.isBest ? Theme.colors.alertSuccess : Theme.colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(14)
            .background(selected ? Theme.colors.primaryAccent4.opacity(0.10) : Theme.colors.bgSurface1)
            .clipShape(Theme.radius.lg.shape)
            .overlay(
                Theme.radius.lg.shape.stroke(selected ? Theme.colors.primaryAccent4 : Theme.colors.borderLight, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapReworkRoute-\(route.option.providerName)")
    }

    private func detail(_ route: SwapRankedRoute) -> String {
        var parts: [String] = []
        if let eta = route.option.etaSeconds { parts.append(SwapReworkFormat.eta(seconds: eta)) }
        if let allIn = route.option.allInFeesFiat {
            parts.append(String(format: "swapReworkAllInFees".localized, SwapReworkFormat.fee(allIn)))
        } else {
            parts.append("swap.included_in_rate".localized)
        }
        return parts.joined(separator: " · ")
    }

    private func gap(_ route: SwapRankedRoute) -> String {
        guard !route.isBest else { return "swapReworkMostToVault".localized }
        var parts = [SwapReworkFormat.gap(route.shortfall, ticker: receiveTicker, isBitcoin: receiveIsBitcoin)]
        if let fiat = route.shortfallFiat, fiat > 0 {
            parts.append("-" + SwapReworkFormat.fee(fiat))
        }
        return parts.joined(separator: " · ")
    }
}
