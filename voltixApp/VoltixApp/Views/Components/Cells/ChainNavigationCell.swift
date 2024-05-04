//
//  ChainNavigationCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import SwiftUI

struct ChainNavigationCell: View {
    let group: GroupedChain
    let vault: Vault
    @Binding var isEditingChains: Bool
    @Binding var totalBalance: Decimal
    @Binding var totalUpdateCount: Int
    
    @State var balanceInFiat: String? = nil
    @State var balanceInDecimal: Decimal? = nil
    
    var body: some View {
        NavigationLink {
            ChainDetailView(group: group, vault: vault, balanceInFiat: balanceInFiat)
        } label: {
            ChainCell(group: group, balanceInFiat: $balanceInFiat, isEditingChains: $isEditingChains, balanceInDecimal: $balanceInDecimal)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .disabled(isEditingChains ? true : false)
        .padding(.vertical, 8)
        .onChange(of: balanceInDecimal) { oldValue, newValue in
            updateTotal(newValue)
        }
    }
    
    private func updateTotal(_ value: Decimal?) {
        totalUpdateCount += 1
        
        guard let value, value>0 else {
            return
        }
        
        totalBalance += value
    }
}

#Preview {
    ChainNavigationCell(
        group: GroupedChain.example,
        vault: Vault.example,
        isEditingChains: .constant(true), totalBalance: .constant(0),
        totalUpdateCount: .constant(0)
    )
}
