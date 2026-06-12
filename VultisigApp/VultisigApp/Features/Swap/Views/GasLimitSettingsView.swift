//
//  GasLimitSettingsView.swift
//  VultisigApp
//
//  Gas Limit sub-sheet: a numeric input that overrides the estimated EVM gas
//  limit. Empty input means Auto (use the estimate). EVM-only — the host only
//  presents this state for EVM source chains.
//

import BigInt
import SwiftUI

struct GasLimitSettingsView: View {
    @Binding var gasLimit: BigUInt?
    let onBack: () -> Void

    @State private var text: String = .empty

    var body: some View {
        VStack(spacing: 12) {
            AdvancedSwapSheetHeader(title: "gasLimit".localized, showBack: true, onClose: onBack)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("gasLimit".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Icon(named: "circle-info", color: Theme.colors.textTertiary, size: 16)
                }

                TextField("auto".localized, text: $text)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .keyboardType(.numberPad)
                    .padding(16)
                    .background(Theme.colors.bgSurface1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.colors.borderExtraLight, lineWidth: 1)
                    )
                    .onChange(of: text) { _, newValue in apply(newValue) }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .onLoad {
            text = gasLimit.map(String.init) ?? .empty
        }
    }

    /// Persist the entered limit. Empty / unparseable / zero clears the override
    /// back to Auto so we never sign with a bogus gas limit.
    private func apply(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let parsed = BigUInt(trimmed), parsed > 0 else {
            gasLimit = nil
            return
        }
        gasLimit = parsed
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var gasLimit: BigUInt?
        var body: some View {
            GasLimitSettingsView(gasLimit: $gasLimit) {}
                .background(Theme.colors.bgPrimary)
        }
    }
    return PreviewContainer()
}
