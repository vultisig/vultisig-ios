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
    
    var showApprove: Bool {
        viewModel.keysignPayload?.approvePayload != nil
    }

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
                with: viewModel.getProvider(),
                showIcon: true
            )
            
            separator
            getValueCell(for: "NetworkFee", with: viewModel.getCalculatedNetworkFee())
        }
        .padding(16)
        .background(Color.blue600)
        .cornerRadius(10)
    }

    var button: some View {
        Button(action: {
            self.viewModel.joinKeysignCommittee()
        }) {
            FilledButton(title: "sign")
        }
        .padding(20)
    }
    
    var summaryTitle: some View {
        Text(NSLocalizedString("youreBridging", comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.lightText)
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
            .foregroundColor(.blue400)
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
            .font(.body12BrockmannMedium)
            .foregroundColor(.persianBlue200)
            .padding(6)
            .background(Color.blue400)
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
                .foregroundColor(.extraLightGray)
            
            Spacer()
            
            if showIcon {
                Image(value)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            
            Text(value)
                .foregroundColor(.neutral0)
            
            if let bracketValue {
                Text(bracketValue)
                    .foregroundColor(.extraLightGray)
            }
            
        }
        .font(.body14BrockmannMedium)
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
                    .foregroundColor(.neutral0) +
                Text(" ") +
                Text(ticker ?? "")
                    .foregroundColor(.extraLightGray)
            }
            .font(.body18BrockmannMedium)
            
            if let chain {
                HStack(spacing: 2) {
                    Text(NSLocalizedString("on", comment: ""))
                        .foregroundColor(.extraLightGray)
                        .padding(.trailing, 4)
                    
                    Image(chain.logo)
                        .resizable()
                        .frame(width: 12, height: 12)
                    
                    Text(chain.name)
                        .foregroundColor(.neutral0)
                    
                    Spacer()
                }
                .font(.body10BrockmannMedium)
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
                .stroke(Color.blue400, lineWidth: 2)
        )
    }
}

#Preview {
    KeysignSwapConfirmView(viewModel: JoinKeysignViewModel())
}
