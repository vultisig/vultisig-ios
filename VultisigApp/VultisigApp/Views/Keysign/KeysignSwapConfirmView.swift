//
//  KeysignSwapConfirmView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.04.2024.
//

import SwiftUI
import BigInt

struct KeysignSwapConfirmView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel

    var body: some View {
        VStack {
            fields
            button
        }
    }

    var fields: some View {
        VStack {
            Spacer()
            summary
            Spacer()
        }
    }

    var summary: some View {
        VStack(spacing: 16) {
            summaryTitle
            summaryFromTo

            separator
            getValueCell(
                for: "provider",
                with: viewModel.providerName,
                showIcon: true
            )

            separator
            getNetworkFeeCell()
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }

    var button: some View {
        PrimaryButton(title: "joinTransactionSigning") {
            viewModel.joinKeysignCommittee()
        }
        .padding(20)
    }

    var summaryTitle: some View {
        Text(NSLocalizedString("youreSwapping", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textSecondary)
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
            .foregroundColor(Theme.colors.bgSurface2)
    }

    var summaryFromTo: some View {
        VStack(spacing: 0) {
            let payload = viewModel.keysignPayload?.swapPayload

            if let fromCoin = payload?.fromCoin {
                getSwapAssetCell(
                    for: viewModel.getFromAmount(),
                    with: payload?.fromCoin.ticker,
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
                    with: payload?.toCoin.ticker,
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
            .foregroundColor(Theme.colors.primaryAccent4)
            .padding(6)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(32)
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
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            if showIcon {
                Image(value)
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            Text(value)
                .foregroundColor(Theme.colors.textPrimary)

            if let bracketValue {
                Text(bracketValue)
                    .foregroundColor(Theme.colors.textTertiary)
            }

        }
        .font(Theme.fonts.bodySMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getNetworkFeeCell() -> some View {
        let fees = viewModel.getCalculatedNetworkFee()
        return HStack(spacing: 4) {
            Text(NSLocalizedString("networkFee", comment: ""))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(fees.feeCrypto)
                    .foregroundColor(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)

                Text(fees.feeFiat)
                    .foregroundColor(Theme.colors.textTertiary)
                    .font(Theme.fonts.caption12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getSwapAssetCell(
        for amount: String?,
        with ticker: String?,
        fiatValue: String,
        on chain: Chain? = nil,
        coin: Coin,
        isTo: Bool
    ) -> some View {
        HStack(spacing: 8) {
            getCoinIcon(for: coin)

            VStack(alignment: .leading, spacing: 4) {
                Text("minPayout".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundColor(Theme.colors.textTertiary)
                    .opacity(isTo ? 1 : 0)

                Text(amount ?? "")
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundColor(Theme.colors.textPrimary)

                HStack(spacing: 0) {
                    Text(fiatValue)
                        .font(Theme.fonts.caption12)
                        .foregroundColor(Theme.colors.textTertiary)
                    Spacer()
                    if let chain {
                        HStack(spacing: 2) {
                            Spacer()

                            Text(NSLocalizedString("on", comment: ""))
                                .foregroundColor(Theme.colors.textTertiary)
                                .padding(.trailing, 4)

                            Image(chain.logo)
                                .resizable()
                                .frame(width: 12, height: 12)

                            Text(chain.name)
                                .foregroundColor(Theme.colors.textPrimary)
                        }
                        .font(Theme.fonts.caption10)
                        .offset(x: 2)
                    }
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
