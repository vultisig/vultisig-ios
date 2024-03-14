//
//  TokenCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct TokenCell: View {
    let asset: Asset
    @State var isSelected = false
    
    @EnvironmentObject var tokenSelectionViewModel: TokenSelectionViewModel
    
    var body: some View {
        HStack {
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
        ZStack {
            
        }
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset.ticker)
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)
            
            Text(asset.chainName)
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
        if tokenSelectionViewModel.selection.contains(asset) {
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
        TokenCell(asset: Asset.example)
            .environmentObject(TokenSelectionViewModel())
    }
}
