//
//  AssetSelectionGridCell.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct AssetSelectionGridCell: View {
    let name: String
    let ticker: String
    let logo: String
    let tokenChainLogo: String?
    @Binding var isSelected: Bool
    var onSelection: () -> Void
    
    init(
        name: String,
        ticker: String,
        logo: String,
        tokenChainLogo: String? = nil,
        isSelected: Binding<Bool>,
        onSelection: @escaping () -> Void
    ) {
        self.name = name
        self.ticker = ticker
        self.logo = logo
        self.tokenChainLogo = tokenChainLogo
        self._isSelected = isSelected
        self.onSelection = onSelection
    }
    
    var body: some View {
        Button {
            isSelected.toggle()
            onSelection()
        } label: {
            VStack(spacing: 10) {
                AsyncImageView(
                    logo: logo,
                    size: CGSize(width: 36, height: 36),
                    ticker: ticker,
                    tokenChainLogo: tokenChainLogo
                )
                .aspectRatio(contentMode: .fit)
                .opacity(isSelected ? 1 : 0.5)
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(isSelected ? Theme.colors.bgSurface1 : Theme.colors.bgButtonDisabled)
                )
                .overlay(isSelected ? selectedOverlay : nil)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .animation(.easeInOut, value: isSelected)
                
                Text(name)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 74, height: 100)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .inset(by: 1)
                .strokeBorder(Theme.colors.border, lineWidth: 1.5)
        }
    }
}

#Preview {
    AssetSelectionGridCell(
        name: "RUNE",
        ticker: "",
        logo: "rune",
        isSelected: .constant(true)
    ) {}
}
