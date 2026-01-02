//
//  TokenSelectionCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct CoinSelectionCell: View {
    let asset: CoinMeta
    @State var isSelected = false
    @EnvironmentObject var tokenSelectionViewModel: CoinSelectionViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            image
            text
            Spacer()
            toggle
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
        .onAppear {
            setData()
        }
        .onChange(of: isSelected) { _, newValue in
            handleSelection(newValue)
        }
        .onTapGesture {
            isSelected.toggle()
        }
    }
    
    var image: some View {
        AsyncImageView(logo: asset.chain.logo, size: CGSize(width: 32, height: 32), ticker: asset.ticker, tokenChainLogo: nil)
    }

    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset.ticker)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(asset.chain.name)
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
    
    var toggle: some View {
        container
    }
    
    var content: some View {
        Toggle("Is selected", isOn: $isSelected)
            .labelsHidden()
            .scaleEffect(0.6)
    }
    
    private func setData() {
        if tokenSelectionViewModel.selection.contains(where: { $0.chain == asset.chain && $0.ticker == asset.ticker }) {
            isSelected = true
        } else {
            isSelected = false
        }
    }
    
    private func handleSelection(_ isSelected: Bool) {
        tokenSelectionViewModel.handleSelection(isSelected: isSelected, asset: asset)
    }
}

#Preview {
    ScrollView {
        CoinSelectionCell(asset: TokensStore.TokenSelectionAssets[0])
            .environmentObject(CoinSelectionViewModel())
    }
}
