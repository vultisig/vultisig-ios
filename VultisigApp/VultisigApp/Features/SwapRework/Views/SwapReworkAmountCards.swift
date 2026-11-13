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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("swapReworkYouPay".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
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

            HStack(alignment: .center, spacing: 12) {
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

                SwapReworkTokenPill(asset: state.pay, action: onTapToken)
                    .accessibilityIdentifier("swapReworkPayToken")
            }

            HStack(alignment: .center, spacing: 8) {
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
                Spacer(minLength: 4)
                SwapReworkPercentChips(isMaxActive: state.gasReserveText != nil, onPercent: onPercent)
                    .fixedSize()
            }
        }
        .padding(16)
        .swapReworkCard(highlighted: isEditing)
    }
}

struct SwapReworkReceiveCard: View {
    let state: SwapReworkFormState
    let onTapToken: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("swapReworkYouReceive".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                Spacer()
                Text(String(format: "swapReworkOnChain".localized, state.receive.chainName))
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 12) {
                receiveAmount
                    .frame(maxWidth: .infinity, alignment: .leading)
                SwapReworkTokenPill(asset: state.receive, action: onTapToken)
                    .accessibilityIdentifier("swapReworkReceiveToken")
            }

            if state.isQuoteLoading {
                SwapReworkSkeleton(width: 120, height: 12)
            } else if !state.receiveFiatText.isEmpty {
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
        .padding(16)
        .swapReworkCard(highlighted: false)
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
