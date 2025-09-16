//
//  ChainGridCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct ChainGridCell: View {
    let assets: [CoinMeta]
    var onSelection: (ChainSelection) -> Void
    
    @State var isSelected = false
    @EnvironmentObject var viewModel: CoinSelectionViewModel
    
    var nativeAsset: CoinMeta {
        assets[0]
    }
    
    var body: some View {
        Button {
            isSelected.toggle()
            onSelection(ChainSelection(selected: isSelected, asset: nativeAsset))
        } label: {
            VStack(spacing: 10) {
                AsyncImageView(
                    logo: nativeAsset.chain.logo,
                    size: CGSize(width: 28, height: 28),
                    ticker: nativeAsset.ticker,
                    tokenChainLogo: nil
                )
                .aspectRatio(contentMode: .fit)
                .opacity(isSelected ? 1 : 0.5)
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(isSelected ? Theme.colors.bgSecondary : Theme.colors.bgButtonDisabled)
                )
                .overlay(isSelected ? selectedOverlay : nil)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .animation(.easeInOut, value: isSelected)
                
                Text(nativeAsset.chain.name)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 74, height: 100)
            .contentShape(Rectangle())
        }
        .onAppear(perform: onAppear)
    }
    
    var selectedOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            Icon(named: "check", color: Theme.colors.alertSuccess, size: 8)
                .padding(8)
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                        topLeading: 24,
                        bottomLeading: 0,
                        bottomTrailing: 24,
                        topTrailing: 0
                    )).fill(Theme.colors.border)
                )
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Theme.colors.border, lineWidth: 1.5)
        }
    }
    
    func onAppear() {
        guard let nativeAsset = assets.first else {
            return
        }
        
        if viewModel.selection.contains(where: { cm in
            cm.chain == nativeAsset.chain && cm.ticker.lowercased() == nativeAsset.ticker.lowercased()
        }) {
            isSelected = true
        } else {
            isSelected = false
        }
    }
}

#Preview {
    ChainGridCell(assets: [.example]) { _ in }
        .environmentObject(CoinSelectionViewModel())
    
}
