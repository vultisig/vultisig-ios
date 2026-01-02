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
            summaryFromToContent
            
            separator
            getValueCell(
                for: "provider",
                with: viewModel.providerName,
                showIcon: true
            )
            
            separator
            getValueCell(for: "NetworkFee", with: viewModel.getJoinedCalculatedNetworkFee())
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
    
    var summaryFromToContent: some View {
        HStack {
            summaryFromToIcons
            summaryFromTo
        }
    }
    
    var summaryFromToIcons: some View {
        VStack(spacing: 0) {
            getCoinIcon(for: viewModel.keysignPayload?.swapPayload?.fromCoin)
            verticalSeparator
            chevronIcon
            verticalSeparator
            getCoinIcon(for: viewModel.keysignPayload?.swapPayload?.toCoin)
        }
    }
    
    var verticalSeparator: some View {
        Rectangle()
            .frame(width: 1, height: 12)
            .foregroundColor(Theme.colors.bgSurface2)
    }
    
    var summaryFromTo: some View {
        VStack(spacing: 16) {
            let payload = viewModel.keysignPayload?.swapPayload
            
            getSwapAssetCell(
                for: viewModel.getFromAmount(),
                with: payload?.fromCoin.ticker,
                on: payload?.fromCoin.chain
            )
            
            separator
                .padding(.leading, 12)
            
            getSwapAssetCell(
                for: viewModel.getToAmount(),
                with: viewModel.keysignPayload?.swapPayload?.toCoin.ticker,
                on: viewModel.keysignPayload?.swapPayload?.toCoin.chain
            )
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
    
    private func getSwapAssetCell(
        for amount: String?,
        with ticker: String?,
        on chain: Chain? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                Text(amount ?? "")
                    .foregroundColor(Theme.colors.textPrimary)
            }
            .font(Theme.fonts.bodyLMedium)
            
            if let chain {
                HStack(spacing: 2) {
                    Text(NSLocalizedString("on", comment: ""))
                        .foregroundColor(Theme.colors.textTertiary)
                        .padding(.trailing, 4)
                    
                    Image(chain.logo)
                        .resizable()
                        .frame(width: 12, height: 12)
                    
                    Text(chain.name)
                        .foregroundColor(Theme.colors.textPrimary)
                    
                    Spacer()
                }
                .font(Theme.fonts.caption10)
                .offset(x: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getCoinIcon(for coin: Coin?) -> some View {
        AsyncImageView(
            logo: coin?.logo ?? "",
            size: CGSize(width: 28, height: 28),
            ticker: coin?.ticker ?? "",
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
