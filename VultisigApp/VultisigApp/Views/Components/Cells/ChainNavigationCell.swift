//
//  ChainNavigationCell.swift
//  VultisigApp
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
    @ObservedObject var sendTx: SendTransaction
    
    @State var balanceInFiat: String? = nil
    @State var balanceInDecimal: Decimal? = nil
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    var body: some View {
        ZStack {
            navigationCell.opacity(0)
            cell
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .disabled(isEditingChains ? true : false)
        .padding(.vertical, 8)
        .onChange(of: balanceInDecimal) { oldValue, newValue in
            updateTotal(newValue)
        }
    }
    
    var cell: some View {
        ChainCell(group: group, balanceInFiat: $balanceInFiat, isEditingChains: $isEditingChains, balanceInDecimal: $balanceInDecimal)
    }
    
    var navigationCell: some View {
        NavigationLink {
            ChainDetailView(group: group, vault: vault, sendTx: sendTx, balanceInFiat: balanceInFiat)
        } label: {
            ChainCell(group: group, balanceInFiat: $balanceInFiat, isEditingChains: $isEditingChains, balanceInDecimal: $balanceInDecimal)
        }
    }
    
    private func updateTotal(_ value: Decimal?) {
        guard let value, totalUpdateCount <= viewModel.coinsGroupedByChains.count else {
            return
        }
        
        totalUpdateCount += 1
        totalBalance += value
    }
}

#Preview {
    ChainNavigationCell(
        group: GroupedChain.example,
        vault: Vault.example,
        isEditingChains: .constant(true), totalBalance: .constant(0),
        totalUpdateCount: .constant(0),
        sendTx: SendTransaction()
    )
    .environmentObject(VaultDetailViewModel())
}
