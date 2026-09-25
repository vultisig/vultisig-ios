//
//  KeysignSwapConfirmView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.04.2024.
//

import SwiftUI
import VultisigUIResources
import BigInt

struct KeysignSwapConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel

    var body: some View {
        VStack {
            fields
            button
        }
    }

    /// Centered while it fits; scrolls once the banner and the optional rows
    /// make it taller than the screen, so the join button is never pushed off.
    var fields: some View {
        GeometryReader { proxy in
            ScrollView {
                summary
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            if let metadata = viewModel.dappMetadata, !metadata.isEmpty {
                DAppRequestBanner(metadata: metadata)
            }
            summaryTitle
            if viewModel.solanaAtaRentState == .failed {
                InfoBannerView(
                    description: "errorNetworkUnstableDescription".localized,
                    type: .warning, leadingIcon: .triangleWarning
                )
                PrimaryButton(title: "retry") {
                    viewModel.retrySolanaAtaRentLookup()
                }
            }
            summaryFromTo

            if let externalRecipient = viewModel.keysignPayload?.swapExternalRecipient {
                separator
                getValueCell(
                    for: "to",
                    with: externalRecipient.truncatedAddress
                )
            }

            separator
            getValueCell(
                for: "provider",
                with: viewModel.providerDisplayName,
                showIcon: true
            )

            if let swapFee = viewModel.getSwapFee() {
                separator
                getFeeCell(title: "swapFee", fees: swapFee)
            }

            separator
            getNetworkFeeCell()

            if !viewModel.priceImpactString.isEmpty {
                separator
                priceImpactRow
            }

            if let totalFee = viewModel.getSwapTotalFee() {
                separator
                getValueCell(for: viewModel.swapFeeLabelKeys.totalFee, with: totalFee)
            }
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(Theme.radius.xl)
    }

    var button: some View {
        PrimaryButton(title: "joinTransactionSigning", isLoading: viewModel.isJoiningCommittee) {
            viewModel.joinKeysignCommittee()
        }
        .disabled(viewModel.isJoiningCommittee || !viewModel.isSolanaFeeReady)
        .padding(20)
    }

    var summaryTitle: some View {
        Text(NSLocalizedString("youreSwapping", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var summaryFromToIcons: some View {
        HStack(spacing: 10) {
            ZStack {
                verticalSeparator
                chevronIcon
            }

            Text("to".localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
            separator
        }
    }

    var verticalSeparator: some View {
        Rectangle()
            .frame(width: 1)
            .frame(idealHeight: 80, maxHeight: 100)
            .foregroundStyle(Theme.colors.bgSurface2)
    }

    var summaryFromTo: some View {
        VStack(spacing: 0) {
            let payload = viewModel.keysignPayload?.swapPayload

            if let fromCoin = payload?.fromCoin {
                getSwapAssetCell(
                    for: viewModel.getFromAmount(),
                    fiatValue: viewModel.getFromFiatAmount(),
                    on: payload?.fromCoin.chain,
                    coin: fromCoin,
                    isTo: false
                )
            }

            summaryFromToIcons

            if let toCoin = payload?.toCoin {
                getSwapAssetCell(
                    for: viewModel.getToAmount(),
                    fiatValue: viewModel.getToFiatAmount(),
                    on: payload?.toCoin.chain,
                    coin: toCoin,
                    isTo: true
                )
            }
        }
    }

    var separator: some View {
        Separator()
            .opacity(0.2)
    }

    var chevronIcon: some View {
        Image(systemName: "arrow.down")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.primaryAccent4)
            .padding(6)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(Theme.radius.pill)
            .bold()
    }

    func getValueCell(
        for title: String,
        with value: String,
        bracketValue: String? = nil,
        showIcon: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            if showIcon {
                VultisigImage(value)
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            Text(value)
                .foregroundStyle(Theme.colors.textPrimary)

            if let bracketValue {
                Text(bracketValue)
                    .foregroundStyle(Theme.colors.textTertiary)
            }

        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priceImpactRow: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("swap.price_impact", comment: "Price Impact"))
                .foregroundStyle(Theme.colors.textTertiary)

            Spacer()

            Text(viewModel.priceImpactString)
                .foregroundStyle(viewModel.priceImpactColor)
        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getNetworkFeeCell() -> some View {
        let fees = viewModel.solanaAtaRentState == .loading
            ? (feeCrypto: "loading".localized, feeFiat: String.empty)
            : viewModel.getCalculatedNetworkFee()
        return getFeeCell(title: viewModel.swapFeeLabelKeys.networkFee, fees: fees)
    }

    private func getFeeCell(title: String, fees: (feeCrypto: String, feeFiat: String)) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(fees.feeCrypto)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)

                Text(fees.feeFiat)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getSwapAssetCell(
        for amount: String?,
        fiatValue: String,
        on chain: Chain? = nil,
        coin: Coin,
        isTo: Bool
    ) -> some View {
        HStack(spacing: 8) {
            getCoinIcon(for: coin)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.toAmountCaptionKey.localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .opacity(isTo ? 1 : 0)

                Text(amount ?? "")
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                HStack(spacing: 0) {
                    Text(fiatValue)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                    Spacer()
                    if let chain {
                        HStack(spacing: 2) {
                            Spacer()

                            Text(NSLocalizedString("on", comment: ""))
                                .foregroundStyle(Theme.colors.textTertiary)
                                .padding(.trailing, 4)

                            VultisigImage(chain.logo)
                                .resizable()
                                .frame(width: 12, height: 12)

                            Text(chain.name)
                                .foregroundStyle(Theme.colors.textPrimary)
                        }
                        .font(Theme.fonts.caption10)
                        .offset(x: 2)
                    }
                }

                // The floor the memo this device is about to sign enforces —
                // the whole point of a co-signer's confirm screen is that the
                // guarantee it approves is the guarantee it signs. Absent on
                // routes that enforce none.
                if isTo, let minPayout = viewModel.getMinPayoutCaption() {
                    Text(minPayout)
                        .font(Theme.fonts.priceCaption)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func getCoinIcon(for coin: Coin) -> some View {
        AsyncImageView(
            logo: coin.logo,
            size: CGSize(width: 28, height: 28),
            ticker: coin.ticker,
            tokenChainLogo: nil
        )
        .overlay(
            Circle()
                .stroke(Theme.colors.bgSurface2, lineWidth: 2)
        )
    }
}

#Preview {
    KeysignSwapConfirmView(viewModel: JoinKeysignViewModel())
}
