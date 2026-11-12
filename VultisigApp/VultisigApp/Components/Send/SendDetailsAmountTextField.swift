//
//  SendDetailsAmountTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-02.
//

import SwiftUI
import VultisigUIResources

struct SendDetailsAmountTextField: View {
    @Bindable var viewModel: SendDetailsViewModel
    @FocusState.Binding var focusedField: Field?

    @State var isCryptoSelected: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The scale a hidden amount block shrinks to when the unit toggles.
    private static let unitSwapHiddenScale: CGFloat = 0.85
    /// Raises the keyboard only once the step has slid in.
    private static let amountFocusDelay: Duration = .milliseconds(350)

    var body: some View {
        HStack {
            inFocusSelector.opacity(0)
            textFieldSection
            inFocusSelector
        }
        .frame(idealHeight: 100, maxHeight: 180)
        // One spring for the swap and the selector pill, so they read as one gesture.
        .animation(unitSwapAnimation, value: isCryptoSelected)
        .onChange(of: focusedField) { _, newValue in
            if newValue == .amount {
                isCryptoSelected = true
            } else if newValue == .amountInFiat {
                isCryptoSelected = false
            }
        }
        .task { await focusAmountAfterSlideIn() }
    }

    /// Leaves focus alone if the user focused a field (memo and tag included) or switched to fiat during the slide.
    private func focusAmountAfterSlideIn() async {
        do {
            try await Task.sleep(for: Self.amountFocusDelay)
        } catch {
            return
        }
        guard viewModel.selectedTab == .amount, focusedField == nil, isCryptoSelected else { return }
        focusedField = .amount
    }

    /// Both blocks stay mounted so focus can hand over between them.
    var textFieldSection: some View {
        ZStack {
            amountSection
                .opacity(isCryptoSelected ? 1 : 0)
                .scaleEffect(isCryptoSelected ? 1 : hiddenScale)
            fiatSection
                .opacity(isCryptoSelected ? 0 : 1)
                .scaleEffect(isCryptoSelected ? hiddenScale : 1)
        }
    }

    private var hiddenScale: CGFloat {
        reduceMotion ? 1 : Self.unitSwapHiddenScale
    }

    private var unitSwapAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.2)
    }

    var inFocusSelector: some View {
        ZStack {
            selectorOvelay

            VStack(spacing: 2) {
                cryptoSelector
                fiatSelector
            }
        }
        .padding(3)
        .background(Theme.colors.bgSurface12)
        .cornerRadius(Theme.radius.pill)
    }

    var selectorOvelay: some View {
        Circle()
            .frame(width: 32, height: 32)
            .foregroundStyle(Theme.colors.bgButtonTertiary)
            .offset(y: isCryptoSelected ? -16 : 16)
    }

    var cryptoSelector: some View {
        Button {
            isCryptoSelected = true
            if focusedField == .amountInFiat {
                focusedField = .amount
            }
        } label: {
            getSelector(for: "circle.dotted.and.circle")
        }
    }

    var fiatSelector: some View {
        Button {
            isCryptoSelected = false
            if focusedField == .amount {
                focusedField = .amountInFiat
            }
        } label: {
            getSelector(for: "dollarsign")
        }
    }

    // Crypto
    var amountSection: some View {
        VStack(spacing: 8) {
            ScalingAmountLine(text: viewModel.amount, unit: viewModel.coin.ticker) { font, animatesDigits in
                amountField(font: font, animatesDigits: animatesDigits)
            }
            amountFiatDescription
        }
    }

    func amountField(font: Font, animatesDigits: Bool) -> some View {
        SendCryptoAmountTextField(
            amount: $viewModel.amount,
            onChange: { viewModel.onAmountFieldEdited($0) },
            onMaxPressed: { viewModel.setMaxAmount() },
            font: font,
            rendersAnimatedDigits: animatesDigits
        )
        .focused($focusedField, equals: .amount)
    }

    var amountFiatDescription: some View {
        getDescriptionText(for: viewModel.amountInFiat.formatToFiat())
            .redacted(reason: viewModel.amountInFiat.isEmpty ? .placeholder : [])
    }

    // Fiat
    var fiatSection: some View {
        VStack(spacing: 4) {
            fiatAmountDescription
            ScalingAmountLine(text: viewModel.amountInFiat, unit: SettingsCurrency.current.rawValue) { font, animatesDigits in
                textFiatField(font: font, animatesDigits: animatesDigits)
            }
        }
    }

    func textFiatField(font: Font, animatesDigits: Bool) -> some View {
        SendCryptoAmountTextField(
            amount: $viewModel.amountInFiat,
            onChange: { viewModel.onFiatAmountFieldEdited($0) },
            font: font,
            rendersAnimatedDigits: animatesDigits
        )
        .focused($focusedField, equals: .amountInFiat)
    }

    var fiatAmountDescription: some View {
        getDescriptionText(for: viewModel.amount.formatToDecimal(digits: 8) + " " + viewModel.coin.ticker)
            .redacted(reason: viewModel.amount.isEmpty ? .placeholder : [])
    }

    private func getDescriptionText(for value: String) -> some View {
        Text(value)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textTertiary)
            .lineLimit(1)
    }

    private func getSelector(for icon: String) -> some View {
        Image(systemName: icon)
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(width: 32, height: 32)
    }
}

/// An amount field and its unit on one line whose font shrinks, no further than
/// `minimumScale`, so the whole figure and unit stay visible instead of the
/// field scrolling sideways. Display only: the field's text is never rewritten.
private struct ScalingAmountLine<Field: View>: View {
    let text: String
    let unit: String
    /// Builds the field with the line's font and whether it may draw rolling digits.
    @ViewBuilder let field: (_ font: Font, _ animatesDigits: Bool) -> Field

    @State private var availableWidth: CGFloat = 0
    @State private var naturalWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fits an 18-decimal amount with four whole digits and a six-letter ticker on an iPhone 17 Pro.
    private static var minimumScale: CGFloat { 0.36 }
    /// The point size behind `Theme.fonts.largeTitle`.
    private static var baseFontSize: CGFloat { 34 }
    private static var baseSpacing: CGFloat { 8 }
    /// Room for the caret, so a line that just fits does not scroll.
    private static var caretAllowance: CGFloat { 4 }
    private static var placeholder: String { "0" }

    var body: some View {
        AmountUnitLine(spacing: Self.baseSpacing * scale) {
            field(font, animatesDigits)
            Text(unit)
                .font(font)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            applyMeasurement(isFirst: availableWidth == 0) { availableWidth = width }
        }
        .background {
            // Measured at full size, so the factor follows the text, not the font it is drawn in.
            HStack(spacing: Self.baseSpacing) {
                Text(text.isEmpty ? Self.placeholder : text)
                Text(unit)
            }
            .font(Theme.fonts.largeTitle)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                applyMeasurement(isFirst: naturalWidth == 0) { naturalWidth = width }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: scale)
    }

    /// The first measurement lands mid-slide, so it applies unanimated and the line travels with the card.
    private func applyMeasurement(isFirst: Bool, _ update: () -> Void) {
        guard isFirst else {
            update()
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private var scale: CGFloat {
        let needed = naturalWidth + Self.caretAllowance
        guard availableWidth > 0, needed > availableWidth else { return 1 }
        return max(availableWidth / needed, Self.minimumScale)
    }

    private var font: Font {
        scale < 1 ? VultisigFont.brockmannMedium.font(size: Self.baseFontSize * scale) : Theme.fonts.largeTitle
    }

    /// Plain glyphs on macOS (AppKit insets differ) and when the line overflows even at the floor (the overlay
    /// cannot follow the field's scroll); unmeasured counts as fitting so the overlay mounts with the pane.
    private var animatesDigits: Bool {
        #if os(iOS)
        let isMeasured = availableWidth > 0 && naturalWidth > 0
        return !isMeasured || (naturalWidth + Self.caretAllowance) * Self.minimumScale <= availableWidth
        #else
        false
        #endif
    }
}

/// An amount field and its unit as one centred line. The field is as wide as
/// its text, up to the room the unit leaves, so the caret stays by the digits
/// and a long amount scrolls inside the field.
private struct AmountUnitLine: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = measure(subviews, availableWidth: proposal.width)
        return CGSize(
            width: proposal.width ?? sizes.field.width + spacing + sizes.unit.width,
            height: max(sizes.field.height, sizes.unit.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = measure(subviews, availableWidth: bounds.width)
        let lineWidth = sizes.field.width + spacing + sizes.unit.width
        let fieldOrigin = CGPoint(x: bounds.midX - lineWidth / 2, y: bounds.midY)
        let unitOrigin = CGPoint(x: fieldOrigin.x + sizes.field.width + spacing, y: bounds.midY)
        subviews[0].place(at: fieldOrigin, anchor: .leading, proposal: ProposedViewSize(sizes.field))
        subviews[1].place(at: unitOrigin, anchor: .leading, proposal: ProposedViewSize(sizes.unit))
    }

    /// Subview 0 is the field, subview 1 the unit.
    private func measure(_ subviews: Subviews, availableWidth: CGFloat?) -> (field: CGSize, unit: CGSize) {
        let unit = subviews[1].sizeThatFits(.unspecified)
        let fieldIdeal = subviews[0].sizeThatFits(.unspecified)
        let room = availableWidth.map { max($0 - unit.width - spacing, 0) } ?? fieldIdeal.width
        let fieldWidth = min(fieldIdeal.width, room)
        let field = subviews[0].sizeThatFits(ProposedViewSize(width: fieldWidth, height: nil))
        return (CGSize(width: fieldWidth, height: field.height), unit)
    }
}
