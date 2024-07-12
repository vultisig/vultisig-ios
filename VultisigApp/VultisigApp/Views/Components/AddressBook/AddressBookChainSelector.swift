//
//  AddressBookChainSelector.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI

struct AddressBookChainSelector: View {
    @Binding var selected: CoinMeta

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
            Text("\(selected.ticker)")
            Spacer()
            Image(systemName: "chevron.down")
        }
        .redacted(reason: selected.balanceString.isEmpty ? .placeholder : [])
        .font(.body16Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
    }
    
    var image: some View {
        AsyncImageView(logo: selected.logo, size: CGSize(width: 32, height: 32), ticker: selected.ticker, tokenChainLogo: selected.tokenChainLogo)
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
    
    private func getCell(for chain: CoinMeta) -> some View {
        HStack(spacing: 12) {
            AsyncImageView(logo: coin.logo, size: CGSize(width: 32, height: 32), ticker: coin.ticker, tokenChainLogo: coin.tokenChainLogo)
            
            Text(coin.ticker)
                .font(.body16Menlo)
                .foregroundColor(.neutral0)

            if let schema = chain.tokenSchema {
                Text("(\(schema))")
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
            }

            Spacer()
            
            if selected == coin {
                Image(systemName: "checkmark")
                    .font(.body16Menlo)
                    .foregroundColor(.neutral0)
            }
        }
        .frame(height: 48)
    }

    private func handleSelection(for chain: CoinMeta?) {
        guard let chain else {
            return
        }
        
        isExpanded = false
        selected = chain
    }
}

#Preview {
    AddressBookChainSelector(selected: .constant(CoinMeta.example))
        .environmentObject(CoinSelectionViewModel())
}
