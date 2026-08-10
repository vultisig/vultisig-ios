//
//  AmountTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import SwiftUI

enum PercentageFieldType {
    case button, slider
}

struct AmountTextField<CustomView: View>: View {
    enum CustomViewPosition {
        case balance
        case bottom
    }

    @Binding var amount: String
    @Binding var error: String?
    let ticker: String
    let type: PercentageFieldType
    let availableAmount: Decimal
    let decimals: Int
    @Binding var percentage: Double?
    let customView: CustomView
    let customViewPosition: CustomViewPosition
    @State var amountInternal: String = ""
    @State var size: CGSize?
    /// The last percentage this field *derived* from a typed amount, as opposed
    /// to one the slider or a percentage button commanded.
    ///
    /// Typing used to blank the percentage outright. That left the slider
    /// reading its `percentage ?? 100` fallback — a confident 100% sitting under
    /// an amount the user had just typed as something else — and hid the
    /// percentage caption entirely. Deriving the percentage instead re-opens the
    /// feedback loop the blanking existed to prevent: a `percentage` change
    /// calls `setupAmount()`, which would overwrite the half-typed amount with a
    /// rounded one on every keystroke.
    ///
    /// So the derived value is remembered and compared. A `percentage` change
    /// equal to it is this field's own echo and is ignored; anything else is a
    /// real interaction with the slider or the buttons and is allowed to set the
    /// amount. A transient boolean flag cannot do this job — `onChange` runs on
    /// the next view update, by which point a flag set and cleared around the
    /// assignment has already been cleared.
    @State private var lastDerivedPercentage: Double?

    init(
        amount: Binding<String>,
        error: Binding<String?>,
        ticker: String,
        type: PercentageFieldType,
        availableAmount: Decimal,
        decimals: Int,
        percentage: Binding<Double?>,
        customViewPosition: CustomViewPosition = .balance,
        customView: () -> CustomView
    ) {
        self._amount = amount
        self._error = error
        self.ticker = ticker
        self.type = type
        self.availableAmount = availableAmount
        self.decimals = decimals
        self._percentage = percentage
        self.customViewPosition = customViewPosition
        self.customView = customView()
        self._amountInternal = State(initialValue: amount.wrappedValue)
    }

    init(
        amount: Binding<String>,
        error: Binding<String?>,
        ticker: String,
        type: PercentageFieldType,
        availableAmount: Decimal,
        decimals: Int,
        percentage: Binding<Double?>
    ) where CustomView == EmptyView {
        self.init(
            amount: amount,
            error: error,
            ticker: ticker,
            type: type,
            availableAmount: availableAmount,
            decimals: decimals,
            percentage: percentage,
            customViewPosition: .balance,
            customView: { EmptyView() }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    TextField("0", text: $amountInternal)
                        .autocorrectionDisabled(true)
                        .multilineTextAlignment(.trailing)
                        .font(Theme.fonts.largeTitle)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .borderlessTextFieldStyle()
                        .fixedSize()
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    Text(ticker)
                        .font(Theme.fonts.largeTitle)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .fixedSize()
                }
                .frame(maxWidth: size?.width)

                if let percentage {
                    Text((Double(percentage) / 100).formatted(.percent))
                        .font(Theme.fonts.subtitle)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                if let error {
                    Text(error.localized)
                        .foregroundStyle(Theme.colors.alertError)
                        .font(Theme.fonts.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                percentageView

                if customViewPosition == .balance {
                    unwrappedCustomView
                }

                availableBalanceView

                if customViewPosition == .bottom {
                    unwrappedCustomView
                }
            }
        }
        .onChange(of: amountInternal) { _, newValue in
            guard amount != newValue else { return }
            amount = newValue
            syncPercentage(toTypedAmount: newValue)
        }
        .onChange(of: amount) { _, newValue in
            amountInternal = newValue
        }
        .onChange(of: percentage) { _, newValue in
            // Our own derived write echoing back. Only a real slider or button
            // interaction may rewrite the amount; see `lastDerivedPercentage`.
            guard newValue != lastDerivedPercentage else { return }
            // A real interaction — so the derived value is spent. Leaving it set
            // would suppress a LATER move back to the same percentage: type the
            // full balance (derives 100), drag to 99%, drag back to 100%, and
            // that last move would be mistaken for the original echo, leaving the
            // amount at 99% while the screen reports a MAX withdrawal.
            lastDerivedPercentage = nil
            setupAmount()
        }
        .onLoad { setupAmount() }
        .onChange(of: availableAmount) { _, _ in
            if percentage != nil, percentage == lastDerivedPercentage {
                // The amount is the user's and the percentage was ours, so the
                // amount is what has to survive a balance that arrived late —
                // re-derive the percentage against the new balance instead of
                // recomputing the amount from it. Blanking the percentage used
                // to give this for free, by making `setupAmount()` return early.
                syncPercentage(toTypedAmount: amountInternal)
            } else {
                setupAmount()
            }
        }
        .readSize(onChange: { size = $0 })
    }

    @ViewBuilder
    var percentageView: some View {
        switch type {
        case .button:
            PercentageButtonsStack(selectedPercentage: $percentage)
        case .slider:
            PercentageSliderView(percentage: $percentage)
        }
    }

    var availableBalanceView: some View {
        HStack {
            Text("balanceAvailable".localized)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            Text("\(availableAmount.formatted(.number.precision(.fractionLength(4)))) \(ticker)")
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .font(Theme.fonts.bodySMedium)
    }

    func setupAmount() {
        guard let percentage else { return }
        let amountDecimal = AmountPercentageBinding.amount(forPercentage: percentage, available: availableAmount)
        amount = amountDecimal.formatToDecimal(digits: decimals)
    }

    /// Points the percentage control at the amount that was just typed, so the
    /// slider and the caption report the share of the balance actually being
    /// acted on.
    func syncPercentage(toTypedAmount typed: String) {
        let derived = AmountPercentageBinding.percentage(ofAmount: typed.toDecimal(), available: availableAmount)
        lastDerivedPercentage = derived
        percentage = derived
    }

    @ViewBuilder
    var unwrappedCustomView: some View {
        if !(customView is EmptyView) {
            customView
        }
    }
}

#Preview {
    @Previewable @State var amount: String = "0"

    VStack {
        AmountTextField(
            amount: $amount,
            error: .constant(nil),
            ticker: "RUNE",
            type: .button,
            availableAmount: 100,
            decimals: 6,
            percentage: .constant(nil)
        )

        AmountTextField(
            amount: $amount,
            error: .constant(nil),
            ticker: "RUNE",
            type: .slider,
            availableAmount: 100,
            decimals: 6,
            percentage: .constant(nil)
        )
    }
    .padding()
    .background(Theme.colors.bgPrimary)
}
