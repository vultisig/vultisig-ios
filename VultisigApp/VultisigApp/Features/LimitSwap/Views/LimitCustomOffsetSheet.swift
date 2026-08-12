//
//  LimitCustomOffsetSheet.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Custom percent-offset sheet
//
// The offset, alone, at the size it deserves — with the price it resolves to
// underneath it, because a percentage is not what gets signed. Nothing is written
// to the draft until Set: holding `+` would otherwise re-derive the amounts on
// every tick of a control the user has not finished operating.

struct LimitCustomOffsetSheet: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var isPresented: Bool

    /// Local until Set. Seeded from the order's live offset, snapped onto the
    /// stepper's own grid — see `limitPctOffsetSeed`.
    @State private var pct: Decimal = 0

    /// The sheet's height, tuned to its content at the default text size — and
    /// SCALED, because the content is text and the detent is not a scroll view.
    /// A pinned 300 would clip the Set button out of reach the moment Dynamic Type
    /// grew the rows above it.
    @ScaledMetric private var sheetHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text("limitSwap.price.customTitle".localized)
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                HStack(spacing: 12) {
                    LimitHoldStepButton(
                        systemImage: "minus",
                        accessibilityLabel: "limitSwap.price.decreaseOffset".localized,
                        isEnabled: pct > limitPctOffsetRange.lowerBound
                    ) { held in
                        apply(clampLimitPctOffset(pct - limitPctStep(forHeldSeconds: held)))
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 4) {
                        Text("\(formatLimitPercent(pct))%")
                            .font(Theme.fonts.priceLargeTitle)
                            .foregroundStyle(offsetTint)
                            .lineLimit(1)
                        // Rolls digit by digit instead of hard-cutting,
                        // which is what makes a held press read as one
                        // continuous movement rather than a flicker.
                            .contentTransition(.numericText())
                            .accessibilityAddTraits(.updatesFrequently)

                        Text(resultingPriceText)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                    }

                    Spacer(minLength: 0)

                    LimitHoldStepButton(
                        systemImage: "plus",
                        accessibilityLabel: "limitSwap.price.increaseOffset".localized,
                        isEnabled: pct < limitPctOffsetRange.upperBound
                    ) { held in
                        apply(clampLimitPctOffset(pct + limitPctStep(forHeldSeconds: held)))
                    }
                }
                .frame(maxWidth: .infinity)

                noticeRow
            }

            PrimaryButton(title: "limitSwap.price.setPrice".localized) {
                vm.pctFromMarketChanged(pct)
                isPresented = false
            }
            .disabled(!isPriceUsable)
        }
        .padding(16)
        #if os(macOS)
        // The toolbar below OVERLAYS its content rather than reserving space, and
        // its close button lands top-leading — exactly where the title starts.
        // iOS doesn't render that toolbar and doesn't want the gap.
        .padding(.top, 32)
        #endif
        .sheetStyle(detents: [.height(sheetHeight)])
        // macOS has no drag-to-dismiss, so without this the sheet has no exit
        // other than committing a value — the same close affordance every other
        // sheet in the app carries.
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark) {
                    isPresented = false
                }
            }
        }
        .onLoad {
            pct = limitPctOffsetSeed(from: vm.pctFromMarket)
        }
    }

    /// One curve for every value change in the sheet, so the digits, the resolved
    /// price and the notice under them all move on the same clock. Deliberately
    /// shorter than `LimitHoldStepButton`'s 80ms repeat: at 120ms every held tick
    /// retargeted a transition that had not finished, and the rolling digits
    /// lagged the press instead of tracking it.
    private static let valueChange: Animation = .snappy(duration: 0.07)

    /// Set `pct`, reporting whether it moved. `false` stops a held repeat that has
    /// walked into the clamp — see `LimitHoldStepButton.onStep`.
    private func apply(_ newValue: Decimal) -> Bool {
        guard newValue != pct else { return false }
        withAnimation(Self.valueChange) {
            pct = newValue
        }
        return true
    }

    /// The target price `pct` resolves to — the number that is actually signed.
    private var previewPrice: Decimal? {
        vm.targetPrice(forPctFromMarket: pct)
    }

    /// Whether the previewed offset names a price the order can actually carry.
    ///
    /// Checked on the RESOLVED price rather than on the percentage, because the
    /// percentage cannot answer it: a zero price is a zero LIM, and a zero LIM
    /// tells THORChain "fill at ANY price" — the one thing a limit order must
    /// never say. The `-99%` floor keeps the stepper clear of that edge and
    /// significant-digit rounding keeps a small price from collapsing into it, so
    /// this is now a guard rather than a routine outcome; it stays because the
    /// sheet is where the number is chosen, and a guard on the signing input is
    /// not something to remove once it looks unreachable.
    private var isPriceUsable: Bool {
        guard let price = previewPrice else { return false }
        return price > 0
    }

    /// What the current offset means for the order — the one thing the percentage
    /// alone cannot say. Named as a value so the row can key its identity on it.
    private enum Notice {
        case unusable
        case belowMarket
        case farAboveMarket
        case rests
    }

    private var notice: Notice {
        guard isPriceUsable else { return .unusable }
        switch previewWarning {
        case .priceAtOrBelowMarket:
            return .belowMarket
        case .priceFarAboveMarket:
            return .farAboveMarket
        case nil:
            return .rests
        }
    }

    /// ALWAYS renders exactly one notice, which is what fixes both halves of the
    /// problem this row had. Reserving a fixed slot for a sometimes-present alert
    /// left a hole in the sheet whenever the offset was unremarkable; letting the
    /// row come and go instead would resize the sheet under the finger mid-hold,
    /// which on a control you hold down is worse. A row that is never empty needs
    /// neither: the height is constant because there is always exactly one line,
    /// and the healthy case earns its space by stating what the order will do.
    ///
    /// The warning cases run the SAME evaluator the form behind the sheet does, so
    /// the two can never contradict each other. Identity is keyed on the case so a
    /// change of meaning crossfades rather than swapping the sentence in place.
    private var noticeRow: some View {
        Group {
            switch notice {
            case .unusable:
                LimitInlineNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Theme.colors.alertWarning,
                    message: "limitSwap.price.offsetPriceUnusable".localized
                )
            case .belowMarket:
                LimitInlineNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Theme.colors.alertWarning,
                    message: "limitSwap.warning.priceAtOrBelowMarket".localized
                )
            case .farAboveMarket:
                LimitInlineNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Theme.colors.alertWarning,
                    message: "limitSwap.warning.priceFarAboveMarket".localized
                )
            case .rests:
                LimitInlineNotice(
                    systemImage: "clock",
                    tint: Theme.colors.alertSuccess,
                    message: "limitSwap.price.offsetRests".localized
                )
            }
        }
        .id(notice)
        .transition(.opacity)
    }

    private var previewWarning: LimitSwapWarning? {
        guard let market = vm.marketPriceRef, let price = previewPrice else { return nil }
        return evaluateWarning(targetPrice: price, marketPrice: market)
    }

    /// "1 BTC = 0.03709 ETH" — the price card's own sentence, so the sheet states
    /// the target in the same direction the form does.
    private var resultingPriceText: String {
        guard let price = previewPrice else {
            return "limitSwap.price.marketLoading".localized
        }
        let value = formatLimitPrice(price)
        return String(
            format: "limitSwap.price.customResult".localized,
            vm.draft.fromAsset.ticker,
            value,
            vm.draft.toAsset.ticker
        )
    }

    /// Same rule as the chip on the form: below market is the one case worth
    /// colouring, because it means the order fills the moment it rests.
    private var offsetTint: Color {
        limitPercentIsEffectivelyZero(pct) || pct > 0
            ? Theme.colors.textPrimary
            : Theme.colors.alertWarning
    }
}
