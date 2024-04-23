//
//  ChainSelectionCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct ChainSelectionCell: View {
    let assets: [Coin]
    
    @State var showAlert = false
    @State var isSelected = false
    @State var asset: Coin? = nil
    
    @EnvironmentObject var tokenSelectionViewModel: TokenSelectionViewModel
    
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
        .redacted(reason: asset==nil ? .placeholder : [])
        .onAppear {
            setData()
        }
        .onChange(of: isSelected) { _, newValue in
            handleSelection(newValue)
        }
    }
    
    var image: some View {
        Image(asset?.logo ?? "Logo")
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(100)
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset?.ticker ?? "Ticker")
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)
            
            Text(asset?.chain.name ?? "Name")
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
        asset = assets.first ?? Coin.example
        
        guard let asset else {
            return
        }
        
        if tokenSelectionViewModel.selection.contains(asset) {
            isSelected = true
        } else {
            isSelected = false
        }
    }
    
    private func handleSelection(_ isSelected: Bool) {
        guard let asset else {
            return
        }
        
        tokenSelectionViewModel.handleSelection(isSelected: isSelected, asset: asset)
    }
}

#Preview {
    ZStack {
        Background()
        ChainSelectionCell(assets: [])
    }
    .environmentObject(TokenSelectionViewModel())
}
