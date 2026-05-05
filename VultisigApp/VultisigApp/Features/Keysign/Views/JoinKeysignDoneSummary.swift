//
//  JoinKeysignDoneSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-05.
//

import SwiftData
import SwiftUI

struct JoinKeysignDoneSummary: View {
    let vault: Vault
    let viewModel: KeysignViewModel
    @Binding var showAlert: Bool

    @Environment(\.openURL) var openURL
    let summaryViewModel = JoinKeysignSummaryViewModel()

    @Query private var vaults: [Vault]
    @Query private var addressBookItems: [AddressBookItem]

    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        VStack {
            Group {
                if viewModel.keysignPayload?.swapPayload != nil {
                    // Check if it's an LP operation by looking at the memo
                    if let memo = viewModel.keysignPayload?.memo,
                       memo.starts(with: "+:") || memo.starts(with: "-:") {
                        // LP operation - show regular send content instead of swap
                        sendContent
                    } else {
                        // Regular swap
                        swapContent
                    }
                } else if viewModel.customMessagePayload == nil {
                    sendContent
                } else {
                    summary
                }
            }
        }
    }

    var summary: some View {
        VStack {
            ScrollView {
                VStack {
                    if let approveTxid = viewModel.approveTxid {
                        card(title: NSLocalizedString("Approve", comment: ""), txid: approveTxid)
                    }
                    content
                }
                .padding(.vertical, 12)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            PrimaryButton(title: "done") {
                onDoneButtonPressed()
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    var content: some View {
        Group {
            signMessageContent
        }
        .padding(.horizontal, 16)
    }

    var swapContent: some View {
        JoinSwapDoneSummary(
            vault: vault,
            keysignViewModel: viewModel,
            summaryViewModel: summaryViewModel,
            showAlert: $showAlert
        )
    }

    private func toAlias(for keysignPayload: KeysignPayload) -> String? {
        SendAddressResolver.resolveAlias(
            address: keysignPayload.toAddress,
            coinMeta: keysignPayload.coin.toCoinMeta(),
            ensLabel: nil,
            vaults: vaults,
            addressBookItems: addressBookItems
        )
    }

    @ViewBuilder
    var sendContent: some View {
        if let keysignPayload = viewModel.keysignPayload {
            let fees = viewModel.getCalculatedNetworkFee()
            SendCryptoDoneContentView(
                input: SendCryptoContent(
                    coin: keysignPayload.coin,
                    amountCrypto: keysignPayload.toAmountWithTickerString,
                    amountFiat: keysignPayload.toSendAmountFiatString,
                    hero: viewModel.heroContent,
                    hash: viewModel.txid,
                    explorerLink: viewModel.getTransactionExplorerURL(txid: viewModel.txid),
                    memo: viewModel.memo ?? "",
                    isSend: true,
                    fromAddress: keysignPayload.coin.address,
                    toAddress: keysignPayload.toAddress,
                    toAlias: toAlias(for: keysignPayload),
                    fee: FeeDisplay(crypto: fees.feeCrypto, fiat: fees.feeFiat),
                    keysignPayload: viewModel.keysignPayload,
                    pubKeyECDSA: vault.pubKeyECDSA,
                    dappMetadata: viewModel.dappMetadata
                ),
                showAlert: $showAlert
            )
        }
    }

    var signMessageContent: some View {
        VStack(spacing: 18) {
            if hasHeroSection {
                doneHeroSection
                Separator()
            }

            getGeneralCell(
                title: "Method",
                description: viewModel.customMessagePayload?.method ?? "",
                isVerticalStacked: true
            )

            Separator()
            // Show decoded message if available, otherwise show raw message
            if let decodedMessage = viewModel.customMessagePayload?.decodedMessage, !decodedMessage.isEmpty {
                getGeneralCell(
                    title: "Transaction Details",
                    description: decodedMessage,
                    isVerticalStacked: true
                )
            } else {
                getGeneralCell(
                    title: "Message",
                    description: viewModel.customMessagePayload?.message ?? "",
                    isVerticalStacked: true
                )
            }
            if let tokenDisplay = viewModel.decodedTokenDisplay,
               !tokenDisplay.isEmpty {
                Separator()
                getGeneralCell(
                    title: "amount",
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
                title: "Signature",
                description: viewModel.customMessageSignature(),
                isVerticalStacked: true
            )
        }

    }

    @ViewBuilder
    private var doneHeroSection: some View {
        if let title = viewModel.decodedFunctionName {
            Text(title)
                .font(Theme.fonts.bodyLMedium)
                .foregroundColor(Theme.colors.textPrimary)
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

    private func onDoneButtonPressed() {
        appViewModel.restart()
    }

    private func getGeneralCell(
        title: String,
        description: String,
        isVerticalStacked: Bool = false,
        isWarning: Bool = false
    ) -> some View {
        let textColor: Color = isWarning ? Theme.colors.alertWarning : Theme.colors.textPrimary
        return ZStack {
            if isVerticalStacked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString(title, comment: ""))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(Theme.colors.textTertiary)

                    HStack(spacing: 6) {
                        Text(description)
                            .foregroundColor(textColor)
                            .font(Theme.fonts.bodySMedium)
                        if isWarning {
                            Icon(named: "triangle-alert", color: textColor, size: 14)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text(NSLocalizedString(title, comment: ""))
                        .foregroundColor(Theme.colors.textTertiary)
                    Spacer()
                    Text(description)
                        .foregroundColor(textColor)
                    if isWarning {
                        Icon(named: "triangle-alert", color: textColor, size: 14)
                    }
                }
                .font(Theme.fonts.bodySMedium)
            }
        }
    }

    private func card(title: String, txid: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleSection(title: title, txid: txid)

            Text(txid)
                .font(Theme.fonts.footnote)
                .foregroundColor(Theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }

    private func titleSection(title: String, txid: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.fonts.bodyLMedium)
                .foregroundColor(Theme.colors.textTertiary)

            copyButton(txid: txid)
            linkButton(txid: txid)
        }
    }

    private func copyButton(txid: String) -> some View {
        Button {
            copyHash(txid: txid)
        } label: {
            Image(systemName: "square.on.square")
                .font(Theme.fonts.bodyLRegular)
                .foregroundColor(Theme.colors.textPrimary)
        }

    }

    private func linkButton(txid: String) -> some View {
        Button {
            shareLink(txid: txid)
        } label: {
            Image(systemName: "link")
                .font(Theme.fonts.bodyLRegular)
                .foregroundColor(Theme.colors.textPrimary)
        }

    }

    private func progressLink(txid: String) -> some View {
        Button {
            if let link = viewModel.getSwapProgressURL(txid: viewModel.txid) {
                progressLink(link: link)
            } else {
                shareLink(txid: txid)
            }
        } label: {
            Text(NSLocalizedString(viewModel.keysignPayload?.swapPayload != nil ? "swapTrackingLink" : "transactionTrackingLink", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.bgButtonPrimary)
                .underline()
                .padding(.vertical, 8)
        }
    }

    private func shareLink(txid: String) {
        let urlString = viewModel.getTransactionExplorerURL(txid: txid)
        if !urlString.isEmpty, let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func progressLink(link: String) {
        if !link.isEmpty, let url = URL(string: link) {
            openURL(url)
        }
    }
}

#Preview {
    ZStack {
        Background()
        JoinKeysignDoneSummary(vault: Vault.example, viewModel: KeysignViewModel(), showAlert: .constant(false))
    }
    .environmentObject(SettingsViewModel())
    .environmentObject(AppViewModel())
}
