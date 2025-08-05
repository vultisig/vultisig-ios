//
//  AddressBookChainSelector.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI

struct AddressBookChainSelector: View {
    @Binding var selected: CoinMeta?

    @State var isExpanded = false
    
    @EnvironmentObject var viewModel: CoinSelectionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedCell
            
            if isExpanded {
                cells
            }
        }
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var selectedCell: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            cell
        }
    }
    
    var cell: some View {
        HStack(spacing: 12) {
            image
            Text("\(selected?.chain.name ?? "")")
            Spacer()
            Image(systemName: "chevron.down")
        }
        .font(Theme.fonts.bodyMRegular)
        .foregroundColor(Theme.colors.textPrimary)
        .frame(height: 48)
    }
    
    var image: some View {
        Image(selected?.chain.logo ?? "")
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(30)
    }
    
    var cells: some View {
        ForEach(viewModel.groupedAssets.keys.sorted(), id: \.self) { key in
            let chain = viewModel.groupedAssets[key]?.first
            Button {
                handleSelection(for: chain)
            } label: {
                VStack(spacing: 0) {
                    Separator()
                    getCell(for: chain)
                }
            }
        }
    }
    
    private func getCell(for coin: CoinMeta?) -> some View {
        HStack(spacing: 12) {
            Image(coin?.chain.logo ?? "")
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(30)
            
            Text(coin?.chain.name ?? "")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)

            Spacer()
            
            if selected == coin {
                Image(systemName: "checkmark")
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundColor(Theme.colors.textPrimary)
            }
        }
        .frame(height: 48)
    }

    private func handleSelection(for coin: CoinMeta?) {
        guard let coin else {
            return
        }
        
        isExpanded = false
        selected = coin
    }
}

#Preview {
    AddressBookChainSelector(selected: .constant(CoinMeta.example))
        .environmentObject(CoinSelectionViewModel())
}
