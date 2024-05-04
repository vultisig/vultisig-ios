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
    @Binding var totalBalance: Decimal
    @Binding var totalUpdateCount: Int
    
    @State var balanceInFiat: String? = nil
    @State var balanceInDecimal: Decimal? = nil
    
    var body: some View {
        NavigationLink {
            ChainDetailView(group: group, vault: vault, balanceInFiat: balanceInFiat)
        } label: {
            ChainCell(group: group, balanceInFiat: $balanceInFiat, balanceInDecimal: $balanceInDecimal)
        }
//        .onAppear {
//            updateTotal(0)
//        }
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
        totalBalance: .constant(0),
        totalUpdateCount: .constant(0))
}
