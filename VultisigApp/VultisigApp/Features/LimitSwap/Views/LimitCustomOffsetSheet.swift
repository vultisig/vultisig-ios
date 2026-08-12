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
        .sheetStyle(detents: [.height(300)])
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
    /// The slot is a fixed height so the big number above it never shifts as
    /// notices come and go — a control whose value jumps under the finger mid-hold
    /// is hard to land. What changes inside it fades, keyed on which notice is
    /// showing so a swap between the two crossfades rather than cutting.
    @ViewBuilder
    private var noticeRow: some View {
        VStack {
            if !isPriceUsable {
                LimitInlineNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Theme.colors.alertWarning,
                    message: "limitSwap.price.offsetPriceUnusable".localized
                )
                .transition(.opacity)
            } else if let warning = previewWarning {
                LimitWarningRow(warning: warning)
                    .id(warning)
                    .transition(.opacity)
            }
        }.frame(height: 50)
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
