//
//  KeysignSignedMessageDoneView.swift
//  VultisigApp
//
//  Done surface for the custom-message keysign (dApp signing) flow.
//  Lifted out of `JoinKeysignDoneSummary.signMessageContent` so the
//  cosigner stack no longer has to dispatch between
//  "tx-broadcast done" and "signed-message done" — `JoinKeysignDoneView`
//  picks one or the other depending on whether `customMessagePayload`
//  is set.
//

import SwiftUI

struct KeysignSignedMessageDoneView: View {
    @ObservedObject var viewModel: KeysignViewModel

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    content
                }
                .padding(.vertical, 12)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            PrimaryButton(title: "done") {
                appViewModel.restart()
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var content: some View {
        VStack(spacing: 18) {
            if hasHeroSection {
                doneHeroSection
                Separator()
            }

            getGeneralCell(
                titleKey: "method",
                description: viewModel.customMessagePayload?.method ?? "",
                isVerticalStacked: true
            )

            Separator()
            if let decodedMessage = viewModel.customMessagePayload?.decodedMessage, !decodedMessage.isEmpty {
                getGeneralCell(
                    titleKey: "transactionDetails",
                    description: decodedMessage,
                    isVerticalStacked: true
                )
            } else {
                getGeneralCell(
                    titleKey: "message",
                    description: viewModel.customMessagePayload?.message ?? "",
                    isVerticalStacked: true
                )
            }
            if let tokenDisplay = viewModel.decodedTokenDisplay,
               !tokenDisplay.isEmpty {
                Separator()
                getGeneralCell(
                    titleKey: "amount",
                    description: tokenDisplay,
                    isVerticalStacked: true,
                    isWarning: viewModel.decodedTokenIsUnlimited
                )
            }
            if hasTransactionDetails {
                Separator()
                DisclosureSection(title: "transactionDetails") {
                    if let signature = viewModel.decodedFunctionSignature, !signature.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("functionSignature".localized)
                                .foregroundStyle(Theme.colors.textTertiary)
                                .font(Theme.fonts.bodySMedium)
                            Text(signature)
                                .foregroundStyle(Theme.colors.turquoise)
                                .font(Theme.fonts.bodySMedium)
                                .textSelection(.enabled)
                        }
                    }
                    if let args = viewModel.decodedFunctionArguments, !args.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("functionArguments".localized)
                                .foregroundStyle(Theme.colors.textTertiary)
                                .font(Theme.fonts.bodySMedium)
                            Text(args)
                                .foregroundStyle(Theme.colors.turquoise)
                                .font(Theme.fonts.bodySMedium)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Separator()
            getGeneralCell(
                titleKey: "signature",
                description: viewModel.customMessageSignature(),
                isVerticalStacked: true
            )
        }
        .padding(.horizontal, 16)
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

    private func getGeneralCell(
        titleKey: String,
        description: String,
        isVerticalStacked: Bool = false,
        isWarning: Bool = false
    ) -> some View {
        let textColor: Color = isWarning ? Theme.colors.alertWarning : Theme.colors.textPrimary
        return ZStack {
            if isVerticalStacked {
                VStack(alignment: .leading, spacing: 8) {
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
            } else {
                HStack {
                    Text(titleKey.localized)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    Text(description)
                        .foregroundStyle(textColor)
                    if isWarning {
                        Icon(named: "triangle-alert", color: textColor, size: 14)
                    }
                }
                .font(Theme.fonts.bodySMedium)
            }
        }
    }
}
