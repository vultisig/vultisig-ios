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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("limitSwap.price.customTitle".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            HStack(spacing: 12) {
                LimitHoldStepButton(
                    systemImage: "minus",
                    accessibilityLabelKey: "limitSwap.price.decreaseOffset",
                    isEnabled: pct > limitPctOffsetRange.lowerBound
                ) { step in
                    apply(clampLimitPctOffset(pct - step))
                }

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    Text("\(formatLimitPercent(pct))%")
                        .font(Theme.fonts.priceLargeTitle)
                        .foregroundStyle(offsetTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        // The number is the control's whole state; announcing it
                        // as it changes is what makes the steppers usable without
                        // sight of it.
                        .accessibilityAddTraits(.updatesFrequently)

                    Text(resultingPriceText)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Spacer(minLength: 0)

                LimitHoldStepButton(
                    systemImage: "plus",
                    accessibilityLabelKey: "limitSwap.price.increaseOffset",
                    isEnabled: pct < limitPctOffsetRange.upperBound
                ) { step in
                    apply(clampLimitPctOffset(pct + step))
                }
            }
            .frame(maxWidth: .infinity)

            noticeRow

            Spacer(minLength: 0)

            PrimaryButton(title: "limitSwap.price.setPrice".localized) {
                vm.pctFromMarketChanged(pct)
                isPresented = false
            }
            .disabled(!isPriceUsable)
        }
        .padding(16)
        // Presented content, not a screen: without this the sheet comes up at
        // full height over a transparent background, showing the form behind it.
        // `sheetStyle` is where the app's sheets get their `bgPrimary` backing and
        // drag indicator. `.medium` rather than a pinned `.height` because the
        // notice row wraps — it is a sentence, and it is a longer one in de/pt —
        // and it grows again with Dynamic Type.
        .sheetStyle(detents: [.medium])
        .onLoad {
            pct = limitPctOffsetSeed(from: vm.pctFromMarket)
        }
    }

    /// Set `pct`, reporting whether it moved. `false` stops a held repeat that has
    /// walked into the clamp — see `LimitHoldStepButton.onStep`.
    private func apply(_ newValue: Decimal) -> Bool {
        guard newValue != pct else { return false }
        pct = newValue
        return true
    }

    /// The target price `pct` resolves to — the number that is actually signed.
    private var previewPrice: Decimal? {
        vm.targetPrice(forPctFromMarket: pct)
    }

    /// Whether the previewed offset names a price the order can actually carry.
    ///
    /// The `-99%` floor is NOT enough on its own, and no fixed percentage could
    /// be: the resolved price is rounded to the memo LIM's 8 decimals, so against
    /// a market small enough (a sub-cent token quoted in BTC) a legal offset still
    /// rounds to zero — and a zero LIM tells THORChain "fill at ANY price". The
    /// form would reject it a step later, but the sheet is where the number is
    /// chosen, so the sheet is where it has to be refused.
    private var isPriceUsable: Bool {
        guard let price = previewPrice else { return false }
        return price > 0
    }

    /// Below the price, the sheet states the one thing the offset alone cannot:
    /// what it means for the order. Priority is refusal first, then the form's own
    /// warnings — running the SAME evaluator the screen behind it does, so the two
    /// can never contradict each other.
    @ViewBuilder
    private var noticeRow: some View {
        if !isPriceUsable {
            LimitInlineNotice(
                systemImage: "exclamationmark.triangle.fill",
                tint: Theme.colors.alertWarning,
                message: "limitSwap.price.offsetPriceUnusable".localized
            )
        } else if let warning = previewWarning {
            LimitWarningRow(warning: warning)
        }
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        let value = formatter.string(from: NSDecimalNumber(decimal: price))
            ?? NSDecimalNumber(decimal: price).stringValue
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
        pct < 0 ? Theme.colors.alertWarning : Theme.colors.textPrimary
    }
}
