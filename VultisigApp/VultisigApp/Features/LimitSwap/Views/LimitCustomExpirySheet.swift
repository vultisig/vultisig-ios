//
//  LimitCustomExpirySheet.swift
//  VultisigApp
//

import SwiftUI

// MARK: - Custom expiry sheet
//
// Edits a DURATION, because a duration is what the memo stores. A date/time
// picker was the original request, but the TTL is a block count started when the
// order joins the queue, so an absolute time chosen here would silently drift by
// the whole deposit-confirmation delay. Days/hours/minutes is the honest control,
// and the copy states what it is relative to.

struct LimitCustomExpirySheet: View {

    @Bindable var vm: LimitSwapFormViewModel
    @Binding var isPresented: Bool

    @State private var days = 0
    @State private var hours = 0
    @State private var minutes = 0

    private var selectedBlocks: Int {
        THORChainConstants.blocks(forMinutes: days * 1440 + hours * 60 + minutes)
    }

    /// The ceiling as this sheet can actually express it. `selectedBlocks` is
    /// always a whole number of minutes, so a mimir cap that isn't a multiple of
    /// `blocksPerMinute` is unreachable — compared raw, the picker would never
    /// register as capped and would keep stepping past a ceiling it can't hit.
    private var representableMaxBlocks: Int {
        THORChainConstants.blocks(
            forMinutes: THORChainConstants.minutes(forBlocks: vm.maxExpiryBlocks)
        )
    }

    private var isAtCeiling: Bool { selectedBlocks >= representableMaxBlocks }
    private var isBelowFloor: Bool { selectedBlocks < vm.minExpiryBlocks }

    /// One curve for every value change in the sheet, so the digits, the notice
    /// swap and the clamped neighbours all move on the same clock. Deliberately
    /// shorter than `LimitHoldStepButton`'s 80ms repeat: a longer curve would
    /// still be running when the next held tick arrives, and the rolling digits
    /// would lag the press instead of tracking it.
    private static let valueChange: Animation = .snappy(duration: 0.07)

    /// The sheet's height, tuned to its content at the default text size — see
    /// `sheetStyle` below for why it scales.
    @ScaledMetric private var sheetHeight: CGFloat = 275

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Scrolls rather than clips, with the action pinned outside it. The
            // detent is a fixed height, so at large Dynamic Type — or in a locale
            // whose notice wraps to three lines — the content would otherwise grow
            // straight past the Set button and put it out of reach. `.basedOnSize`
            // means it does not feel scrollable until it actually is.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("limitSwap.expiry.customTitle".localized)
                            .font(Theme.fonts.bodyLMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Spacer()
                        Text(String(
                            format: "limitSwap.expiry.maxHint".localized,
                            formatLimitExpiry(blocks: vm.maxExpiryBlocks)
                        ))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                    }

                    // Bounded left to right against ONE allowance, not three
                    // independent ranges — see `limitExpiryHoursCeiling`. At the
                    // 3-day ceiling that pins hours and minutes to 0, so the
                    // control cannot spell a duration THORChain would silently
                    // rewrite.
                    HStack(spacing: 10) {
                        stepper(titleKey: "limitSwap.expiry.daysUnit", value: $days, range: 0...maxDays)
                        stepper(titleKey: "limitSwap.expiry.hoursUnit", value: $hours, range: 0...maxHours)
                        stepper(titleKey: "limitSwap.expiry.minutesUnit", value: $minutes, range: 0...maxMinutes, step: 5)
                    }

                    noticeRow
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            PrimaryButton(title: "limitSwap.expiry.set".localized) {
                vm.selectExpiryBlocks(selectedBlocks)
                isPresented = false
            }
            .disabled(isBelowFloor)
        }
        .padding(16)
        #if os(macOS)
        // The toolbar below OVERLAYS its content rather than reserving space, and
        // its close button lands top-leading — exactly where the title starts.
        // iOS doesn't render that toolbar and doesn't want the gap, which this
        // fixed-height sheet can least afford to lose.
        .padding(.top, 32)
        #endif
        // Scaled, not pinned: the content is text and there is no scroll view
        // under the Set button, so a fixed height would clip it out of reach as
        // Dynamic Type grew the rows above.
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
        // Spending the allowance left to right means a change upstream can leave
        // a downstream value over its new ceiling — setting Days to 3 against a
        // 3-day cap has to empty Hours and Minutes rather than leave them
        // describing a duration that no longer fits.
        .onChange(of: days) { _, _ in
            withAnimation(Self.valueChange) {
                hours = min(hours, maxHours)
                minutes = min(minutes, maxMinutes)
            }
        }
        .onChange(of: hours) { _, _ in
            withAnimation(Self.valueChange) {
                minutes = min(minutes, maxMinutes)
            }
        }
        .onLoad {
            // Seed from the live draft so reopening the sheet shows what is set.
            let total = THORChainConstants.minutes(forBlocks: vm.draft.expiryBlocks)
            days = total / 1440
            hours = (total % 1440) / 60
            minutes = total % 60
        }
    }

    /// The ceiling, in minutes — the single allowance the three steppers divide
    /// between them.
    private var maxTotalMinutes: Int {
        THORChainConstants.minutes(forBlocks: vm.maxExpiryBlocks)
    }

    private var maxDays: Int { maxTotalMinutes / 1440 }

    private var maxHours: Int {
        limitExpiryHoursCeiling(maxTotalMinutes: maxTotalMinutes, days: days)
    }

    private var maxMinutes: Int {
        limitExpiryMinutesCeiling(maxTotalMinutes: maxTotalMinutes, days: days, hours: hours)
    }

    /// Which of the three notices the current duration earns. Named as a value so
    /// the row below can key its identity on it — see `noticeRow`.
    private enum Notice {
        case ceiling
        case floor
        case rests
    }

    private var notice: Notice {
        if isAtCeiling { return .ceiling }
        if isBelowFloor { return .floor }
        return .rests
    }

    /// Says which bound was hit and why, instead of letting the value be silently
    /// corrected. THORChain clamps an over-long TTL on-chain without an error, so
    /// an app that mirrored that behaviour would leave the user believing they had
    /// set a week.
    ///
    /// The three are alternatives, not one row whose text is rewritten, so the row
    /// takes its identity from which one is showing: that is what makes crossing a
    /// bound crossfade rather than swap the string in place mid-sentence. Within a
    /// case the text still updates silently, which is right — the duration ticking
    /// up is the same statement, not a new one.
    @ViewBuilder
    private var noticeRow: some View {
        Group {
            switch notice {
            case .ceiling:
                LimitInlineNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Theme.colors.alertWarning,
                    message: String(
                        format: "limitSwap.expiry.ceilingNotice".localized,
                        formatLimitExpiry(blocks: vm.maxExpiryBlocks)
                    )
                )
            case .floor:
                LimitInlineNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Theme.colors.alertWarning,
                    message: String(
                        format: "limitSwap.expiry.floorNotice".localized,
                        formatLimitExpiry(blocks: vm.minExpiryBlocks)
                    )
                )
            case .rests:
                LimitInlineNotice(
                    systemImage: "clock",
                    tint: Theme.colors.alertSuccess,
                    message: String(
                        format: "limitSwap.expiry.restsFor".localized,
                        formatLimitExpiry(blocks: selectedBlocks)
                    )
                )
            }
        }
        .id(notice)
        .transition(.opacity)
    }

    private func stepper(titleKey: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        VStack(spacing: 6) {
            Text(titleKey.localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                // The same press-and-hold control the offset sheet uses, at this
                // row's size. The step does NOT accelerate here, and that is the
                // point of the button taking a schedule rather than owning one:
                // these ranges are 4 to 24 steps end to end, so a constant repeat
                // already crosses them in about a second and anything faster would
                // be impossible to land on a value.
                LimitHoldStepButton(
                    systemImage: "minus",
                    accessibilityLabel: String(
                        format: "limitSwap.expiry.decreaseUnit".localized,
                        titleKey.localized
                    ),
                    isEnabled: value.wrappedValue > range.lowerBound,
                    diameter: 24,
                    glyphPointSize: 11
                ) { _ in
                    set(value, to: limitStepperDecrement(
                        value.wrappedValue,
                        step: step,
                        lowerBound: range.lowerBound
                    ))
                }

                Text("\(value.wrappedValue)")
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .contentTransition(.numericText())
                    .frame(minWidth: 26)

                LimitHoldStepButton(
                    systemImage: "plus",
                    accessibilityLabel: String(
                        format: "limitSwap.expiry.increaseUnit".localized,
                        titleKey.localized
                    ),
                    isEnabled: value.wrappedValue < range.upperBound,
                    diameter: 24,
                    glyphPointSize: 11
                ) { _ in
                    set(value, to: limitStepperIncrement(
                        value.wrappedValue,
                        step: step,
                        upperBound: range.upperBound
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .overlay(
            Theme.radius.md.shape
                .stroke(Theme.colors.borderLight, lineWidth: 1)
        )
        .clipShape(Theme.radius.md.shape)
    }

    /// Writes `newValue` and reports whether it MOVED — which is what stops a held
    /// repeat once the stepper has walked into its bound.
    private func set(_ binding: Binding<Int>, to newValue: Int) -> Bool {
        guard newValue != binding.wrappedValue else { return false }
        withAnimation(Self.valueChange) {
            binding.wrappedValue = newValue
        }
        return true
    }
}
