//
//  SwapReworkAmountCards.swift
//  VultisigApp
//
//  "You pay" and "You receive": the amount is the hero (large tabular
//  numerals), the token pill keeps a fixed slot on the right, and balance,
//  % chips and the gas Max keeps behind sit on the card itself.
//

import SwiftUI

struct SwapReworkPayCard: View {
    let state: SwapReworkFormState
    let isEditing: Bool
    let onTapAmount: () -> Void
    let onTapToken: () -> Void
    let onPercent: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(16)
        .swapReworkCard(highlighted: isEditing)
    }

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                title
                Spacer(minLength: 4)
                balance
            }
            HStack(alignment: .center, spacing: 8) {
                amountButton
                Spacer(minLength: 4)
                pill
            }
            HStack(alignment: .center, spacing: 8) {
                fiatOrReserve
                Spacer(minLength: 4)
                chips
            }
        }
    }

    /// R4 1_03: one thing per line, in reading order: the amount gets the full
    /// width, the pill drops below it, then fiat, balance and the chips.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            title
            amountButton
            pill
            fiatOrReserve
            balance
            chips
        }
    }

    private var title: some View {
        Text("swapReworkYouPay".localized)
            .font(Theme.fonts.footnote)
            .foregroundStyle(Theme.colors.textTertiary)
    }

    private var balance: some View {
        HStack(spacing: 4) {
            Text("swapReworkBalance".localized)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(state.balanceText)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .font(Theme.fonts.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var amountButton: some View {
        Button(action: onTapAmount) {
            HStack(spacing: 2) {
                Text(SwapKeypadInput.display(state.amountText))
                    .font(Theme.fonts.priceLargeTitle)
                    .monospacedDigit()
                    .foregroundStyle(state.isEmpty ? Theme.colors.textTertiary : Theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                if isEditing {
                    SwapReworkCaret()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapReworkPayAmount")
    }

    private var pill: some View {
        SwapReworkTokenPill(asset: state.pay, action: onTapToken)
            .accessibilityIdentifier("swapReworkPayToken")
    }

    @ViewBuilder
    private var fiatOrReserve: some View {
        if let reserve = state.gasReserveText {
            VStack(alignment: .leading, spacing: 0) {
                Text("swapReworkReservedForGas".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                Text(reserve)
                    .font(Theme.fonts.priceCaption)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .layoutPriority(-1)
        } else {
            Text(state.payFiatText)
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
        }
    }

    private var chips: some View {
        SwapReworkPercentChips(isMaxActive: state.gasReserveText != nil, onPercent: onPercent)
            .fixedSize()
    }
}

struct SwapReworkReceiveCard: View {
    let state: SwapReworkFormState
    let onTapToken: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(16)
        .swapReworkCard(highlighted: false)
    }

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("swapReworkYouReceive".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer(minLength: 4)
                Text(String(format: "swapReworkOnChain".localized, state.receive.chainName))
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 8) {
                receiveAmount
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 4)
                pill
            }
            if state.isQuoteLoading {
                SwapReworkSkeleton(width: 120, height: 12)
            } else if showsFiat {
                HStack(spacing: 4) {
                    Text(state.receiveFiatText)
                    if let allIn = state.allInText {
                        Text("·")
                        Text(allIn)
                    }
                }
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    /// R4 1_03: "You receive on Bitcoin" on one line, then the amount, the pill
    /// below it, fiat and the all-in each on their own line.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: "swapReworkYouReceiveOn".localized, state.receive.chainName))
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textTertiary)
            receiveAmount
                .frame(maxWidth: .infinity, alignment: .leading)
            pill
            if state.isQuoteLoading {
                SwapReworkSkeleton(width: 120, height: 12)
            } else if showsFiat {
                Text(state.receiveFiatText)
                    .font(Theme.fonts.priceFootnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                if let allIn = state.allInText {
                    Text(allIn)
                        .font(Theme.fonts.priceFootnote)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
        }
    }

    private var showsFiat: Bool {
        !state.receiveFiatText.isEmpty && state.issue != .noRoute
    }

    private var pill: some View {
        SwapReworkTokenPill(asset: state.receive, action: onTapToken)
            .accessibilityIdentifier("swapReworkReceiveToken")
    }

    @ViewBuilder
    private var receiveAmount: some View {
        if state.isQuoteLoading && !state.isReceiveIndicative {
            SwapReworkSkeleton(width: 180, height: 36)
        } else {
            Text(state.issue == .noRoute ? "—" : state.receiveAmountText)
                .font(Theme.fonts.priceLargeTitle)
                .monospacedDigit()
                .foregroundStyle(receiveColor)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .padding(.horizontal, state.highlightsReceive ? 6 : 0)
                .background(
                    Theme.radius.sm.shape
                        .fill(Theme.colors.alertWarning.opacity(state.highlightsReceive ? 0.18 : 0))
                )
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: state.receiveAmountText)
                .accessibilityIdentifier("swapReworkReceiveAmount")
        }
    }

    private var receiveColor: Color {
        if state.isReceiveIndicative || state.receiveAmountText == "0" { return Theme.colors.textTertiary }
        return Theme.colors.textSecondary
    }
}

struct SwapReworkTokenPill: View {
    let asset: SwapReworkAsset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AsyncImageView(
                    logo: asset.logo,
                    size: CGSize(width: 28, height: 28),
                    ticker: asset.ticker,
                    tokenChainLogo: asset.chainLogo
                )
                Text(asset.ticker)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Theme.colors.bgSurface2)
            .clipShape(Capsule())
            .fixedSize()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SwapReworkPercentChips: View {
    let isMaxActive: Bool
    let onPercent: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            chip("25%", identifier: "swapRework25") { onPercent(25) }
            chip("50%", identifier: "swapRework50") { onPercent(50) }
            chip("swapReworkMax".localized, identifier: "swapReworkMax", active: isMaxActive) { onPercent(100) }
        }
    }

    private func chip(_ title: String, identifier: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(active ? Theme.colors.primaryAccent4 : Theme.colors.textPrimary)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(active ? Theme.colors.primaryAccent4.opacity(0.16) : Theme.colors.bgSurface2)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

struct SwapReworkFlipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
                .background(Theme.colors.bgSurface2)
                .clipShape(Theme.radius.md.shape)
                .overlay(Theme.radius.md.shape.stroke(Theme.colors.bgPrimary, lineWidth: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("swapReworkFlip".localized)
        .accessibilityIdentifier("swapReworkFlip")
    }
}

struct SwapReworkCaret: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Theme.colors.primaryAccent4)
            .frame(width: 2, height: 34)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever()) { visible = false }
            }
            .accessibilityHidden(true)
    }
}

struct SwapReworkSkeleton: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Theme.radius.sm.shape
            .fill(Theme.colors.bgSurface2)
            .frame(width: width, height: height)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The R3 card: surface fill, hairline border, a blue border while active.
    func swapReworkCard(highlighted: Bool) -> some View {
        self
            .background(Theme.colors.bgSurface1)
            .clipShape(Theme.radius.lg.shape)
            .overlay(
                Theme.radius.lg.shape
                    .stroke(highlighted ? Theme.colors.primaryAccent4 : Theme.colors.borderLight, lineWidth: 1)
            )
    }
}
