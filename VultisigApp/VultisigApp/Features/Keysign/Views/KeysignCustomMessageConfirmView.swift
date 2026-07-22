//
//  KeysignCustomMessageConfirmView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 30.11.2024.
//

import SwiftUI

struct KeysignCustomMessageConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel
    @State private var isMessageExpanded: Bool = false
    @State private var isTransactionDetailsExpanded: Bool = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                title
                summary
                button
            }
            .foregroundStyle(Theme.colors.textPrimary)
            .task {
                await viewModel.loadFunctionName()
            }
        }
    }

    var title: some View {
        Text(NSLocalizedString("verify", comment: ""))
            .frame(maxWidth: .infinity, alignment: .center)
            .font(Theme.fonts.bodyLMedium)
    }

    var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                if hasHeroSection {
                    heroSection
                    Separator()
                }
                method
                Separator()
                message
                if let tokenDisplay = viewModel.decodedTokenDisplay,
                   !tokenDisplay.isEmpty {
                    Separator()
                    getPrimaryCell(
                        title: "amount",
                        value: tokenDisplay,
                        isWarning: viewModel.decodedTokenIsUnlimited
                    )
                }
                if hasTransactionDetails {
                    Separator()
                    transactionDetailsSection
                }
            }
            .padding(16)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(10)
            .padding(16)
        }
    }

    @ViewBuilder
    var heroSection: some View {
        if let title = viewModel.decodedFunctionName {
            Text(title)
                .font(Theme.fonts.bodyLMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var hasHeroSection: Bool {
        viewModel.decodedFunctionName != nil
    }

    var hasTransactionDetails: Bool {
        let hasSignature = !(viewModel.decodedFunctionSignature?.isEmpty ?? true)
        let hasArguments = !(viewModel.decodedFunctionArguments?.isEmpty ?? true)
        return hasSignature || hasArguments
    }

    var method: some View {
        getPrimaryCell(title: "Method", value: viewModel.customMessagePayload?.method ?? "")
    }

    var message: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isMessageExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text(NSLocalizedString("message", comment: "") + ":")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Icon(.chevronDown, color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isMessageExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isMessageExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(formattedMessage)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Formats the message for display - decodes hex if needed
    private var formattedMessage: String {
        guard let payload = viewModel.customMessagePayload else { return "" }

        if let decoded = payload.decodedMessage, !decoded.isEmpty {
            return decoded
        }

        // Fallback: try hex to UTF-8
        if payload.message.hasPrefix("0x") {
            let hex = String(payload.message.dropFirst(2))
            if let data = Data(hexString: hex), let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }
        }

        return payload.message
    }

    var button: some View {
        PrimaryButton(title: "joinKeysign", isLoading: viewModel.isJoiningCommittee) {
            viewModel.joinKeysignCommittee()
        }
        .disabled(viewModel.isJoiningCommittee)
        .padding(20)
    }

    var transactionDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    isTransactionDetailsExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text("transactionDetails".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Icon(.chevronDown, color: Theme.colors.textTertiary, size: 16)
                        .rotationEffect(.degrees(isTransactionDetailsExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.borderless)

            if isTransactionDetailsExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let signature = viewModel.decodedFunctionSignature, !signature.isEmpty {
                            getPrimaryCell(title: "functionSignature", value: signature)
                        }

                        if let args = viewModel.decodedFunctionArguments, !args.isEmpty {
                            getPrimaryCell(title: "functionArguments", value: args)
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.colors.bgSurface2))
            }
        }
    }

    private func getPrimaryCell(title: String, value: String, isWarning: Bool = false) -> some View {
        let textColor: Color = isWarning ? Theme.colors.alertWarning : Theme.colors.textPrimary
        return VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString(title, comment: "") + ":")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            HStack(spacing: 6) {
                Text(value)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(textColor)
                if isWarning {
                    Icon(.triangleWarning, color: textColor, size: 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
