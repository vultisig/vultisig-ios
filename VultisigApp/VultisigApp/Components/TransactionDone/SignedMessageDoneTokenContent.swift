//
//  SignedMessageDoneTokenContent.swift
//  VultisigApp
//
//  `tokenContent` slot rendered by `DoneScreen` on the custom-message
//  cosigner path. Lifted from the deleted `KeysignSignedMessageDoneView`
//  so the dApp-signing done flow uses the same `DoneScreen` chrome
//  (Screen + status header + bottom bar) as Send / Swap / QBTC.
//
//  Renders, top-down:
//    - Decoded function name (when available).
//    - `method` cell — the EIP-712 / signing method name.
//    - `transactionDetails` (when a decoded message exists) or `message`.
//    - `amount` cell, marked as warning when the token approval is
//      unlimited.
//    - Expandable `transactionDetails` disclosure for decoded function
//      signature + arguments.
//    - `signature` cell — the produced signature blob.
//

import SwiftUI

struct SignedMessageDoneTokenContent: View {
    @ObservedObject var viewModel: KeysignViewModel

    var body: some View {
        VStack(spacing: 18) {
            if hasHeroSection {
                doneHeroSection
                Separator()
            }

            cell(
                titleKey: "method",
                description: viewModel.customMessagePayload?.method ?? ""
            )
            Separator()

            if let decodedMessage = viewModel.customMessagePayload?.decodedMessage, !decodedMessage.isEmpty {
                cell(titleKey: "transactionDetails", description: decodedMessage)
            } else {
                cell(titleKey: "message", description: viewModel.customMessagePayload?.message ?? "")
            }

            if let tokenDisplay = viewModel.decodedTokenDisplay, !tokenDisplay.isEmpty {
                Separator()
                cell(
                    titleKey: "amount",
                    description: tokenDisplay,
                    isWarning: viewModel.decodedTokenIsUnlimited
                )
            }

            if hasTransactionDetails {
                Separator()
                DisclosureSection(title: "transactionDetails") {
                    if let signature = viewModel.decodedFunctionSignature, !signature.isEmpty {
                        labelledBlock(titleKey: "functionSignature", value: signature)
                    }
                    if let args = viewModel.decodedFunctionArguments, !args.isEmpty {
                        labelledBlock(titleKey: "functionArguments", value: args)
                    }
                }
            }

            Separator()
            cell(titleKey: "signature", description: viewModel.customMessageSignature())
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var doneHeroSection: some View {
        if let title = viewModel.decodedFunctionName {
            Text(title)
                .font(Theme.fonts.bodyLMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var hasTransactionDetails: Bool {
        let hasSignature = !(viewModel.decodedFunctionSignature?.isEmpty ?? true)
        let hasArguments = !(viewModel.decodedFunctionArguments?.isEmpty ?? true)
        return hasSignature || hasArguments
    }

    private var hasHeroSection: Bool {
        viewModel.decodedFunctionName != nil
    }

    private func cell(titleKey: String, description: String, isWarning: Bool = false) -> some View {
        let textColor: Color = isWarning ? Theme.colors.alertWarning : Theme.colors.textPrimary
        return VStack(alignment: .leading, spacing: 8) {
            Text(titleKey.localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)

            HStack(spacing: 6) {
                Text(description)
                    .foregroundStyle(textColor)
                    .font(Theme.fonts.bodySMedium)
                if isWarning {
                    Icon(named: "triangle-alert", color: textColor, size: 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelledBlock(titleKey: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey.localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)
            Text(value)
                .foregroundStyle(Theme.colors.turquoise)
                .font(Theme.fonts.bodySMedium)
                .textSelection(.enabled)
        }
    }
}
