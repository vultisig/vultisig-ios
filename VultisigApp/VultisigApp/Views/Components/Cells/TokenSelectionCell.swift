//
//  TokenSelectionCell.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.05.2024.
//

import SwiftUI

struct TokenSelectionCell: View {
    let chain: Chain
    let asset: OneInchToken
    @State var isSelected = false

    @EnvironmentObject var tokenSelectionViewModel: TokenSelectionViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel


    var body: some View {
        HStack(spacing: 16) {
            image
            text
            Spacer()
            toggle
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
        .onAppear {
            setData()
        }
        .onChange(of: isSelected) { _, newValue in
            handleSelection(newValue)
        }
    }

    var image: some View {
        ImageView(
            source: .remote(asset.logoURI),
            size: CGSize(width: 32, height: 32)
        )
    }

    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset.symbol)
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)

            Text(chain.name)
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
        }
    }

    var toggle: some View {
        Toggle("Is selected", isOn: $isSelected)
            .labelsHidden()
            .scaleEffect(0.6)
    }

    private func setData() {
        if coinSelectionViewModel.selection.contains(convertToCoin(asset)) {
            isSelected = true
        } else {
            isSelected = false
        }
    }

    private func handleSelection(_ isSelected: Bool) {
        coinSelectionViewModel.handleSelection(isSelected: isSelected, asset: convertToCoin(asset))
    }

    private func convertToCoin(_ token: OneInchToken) -> Coin {
        return Coin(
            chain: chain,
            ticker: token.symbol,
            logo: token.logoURI.absoluteString,
            address: .empty,
            priceRate: 0,
            chainType: .EVM,
            decimals: String(token.decimals),
            hexPublicKey: .empty,
            feeUnit: "Gwei",
            priceProviderId: "\(chain.coingeckoId)_\(token.address)",
            contractAddress: token.address,
            rawBalance: .zero,
            isNativeToken: false,
            feeDefault: "120000"
        )
    }
}

#Preview {
    ScrollView {
        CoinSelectionCell(asset: Coin.example)
            .environmentObject(CoinSelectionViewModel())
    }
}

