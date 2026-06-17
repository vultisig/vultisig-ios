//
//  SlippageSettingsView.swift
//  VultisigApp
//
//  Slippage sub-sheet: helper copy + radio rows (Auto / 0.5% / 1% / 3% /
//  Custom). Custom reveals a numeric input. Selecting any row writes back to the
//  bound `SwapSlippage`; navigation back to Main is the host's responsibility.
//

import SwiftUI

struct SlippageSettingsView: View {
    @Binding var slippage: SwapSlippage
    let onBack: () -> Void

    @State private var customText: String = .empty
    @State private var didClampCustom = false
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            AdvancedSwapSheetHeader(title: "slippage".localized, showBack: true, onClose: onBack)

            Text("slippageHelperText".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                radioRow(title: "auto".localized, isSelected: isAuto) {
                    slippage = .auto
                    customFocused = false
                }
                Separator()

                ForEach(SwapSlippage.presets, id: \.self) { bps in
                    radioRow(title: SwapSlippage.format(bps: bps), isSelected: isPreset(bps)) {
                        slippage = .preset(bps: bps)
                        customFocused = false
                    }
                    Separator()
                }

                customRow
            }
            .background(Theme.colors.bgSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
            .padding(.horizontal, 16)

            if didClampCustom {
                Text(String(format: "slippageMaxNote".localized, SwapSlippage.format(bps: SwapSlippage.maxCustomBps)))
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.alertWarning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)
        }
        .onLoad {
            if case let .custom(bps) = slippage {
                customText = SwapSlippage.format(bps: bps).replacingOccurrences(of: "%", with: "")
            }
        }
    }

    private var customRow: some View {
        Button {
            customFocused = true
            applyCustom()
        } label: {
            HStack(spacing: 8) {
                Text("custom".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)

                customField
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .focused($customFocused)
                    .frame(width: 64)
                    .onChange(of: customText) { _, _ in applyCustom() }

                Spacer()
                radioIndicator(isSelected: isCustom)
            }
            .padding(24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Custom slippage input. `keyboardType` is iOS-only, so it's applied behind
    /// a platform guard; macOS uses the bare field.
    @ViewBuilder
    private var customField: some View {
        let field = TextField("0.00%", text: $customText)
        #if os(iOS)
        field.keyboardType(.decimalPad)
        #else
        field
        #endif
    }

    private func radioRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                Spacer()
                radioIndicator(isSelected: isSelected)
            }
            .padding(24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func radioIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Theme.colors.alertSuccess : Theme.colors.borderLight, lineWidth: 1.5)
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
        }
    }

    private var isAuto: Bool { slippage == .auto }
    private func isPreset(_ bps: Int) -> Bool { slippage == .preset(bps: bps) }
    private var isCustom: Bool {
        if case .custom = slippage { return true }
        return false
    }

    /// Parse the custom-percent text into basis points and write it back. Empty
    /// or unparseable input falls back to `Auto` so we never persist a bogus value.
    /// The basis-points value is clamped to `SwapSlippage.maxCustomBps` (50%) so an
    /// absurd tolerance never reaches a provider; when the entered value exceeds the
    /// cap the field is rewritten to the clamped percent and an inline note shows.
    private func applyCustom() {
        let trimmed = customText.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let percent = Decimal(string: trimmed), percent > 0 else {
            didClampCustom = false
            if customFocused { slippage = .auto }
            return
        }
        let rawBps = (percent * 100 as NSDecimalNumber).intValue
        let bps = SwapSlippage.clampCustomBps(rawBps)
        if bps != rawBps {
            didClampCustom = true
            // Reflect the enforced cap back into the field so the displayed value
            // matches what's actually applied.
            customText = SwapSlippage.format(bps: bps).replacingOccurrences(of: "%", with: "")
        } else {
            didClampCustom = false
        }
        slippage = .custom(bps: bps)
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var slippage: SwapSlippage = .auto
        var body: some View {
            SlippageSettingsView(slippage: $slippage) {}
                .background(Theme.colors.bgPrimary)
        }
    }
    return PreviewContainer()
}
