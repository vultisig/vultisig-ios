//
//  ChainCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct ChainCell: View {
    @ObservedObject var group: GroupedChain
    @Binding var isEditingChains: Bool
    
    @State var showAlert = false
    @State var showQRcode = false
    
    @StateObject var viewModel = ChainCellViewModel()
    @EnvironmentObject var homeViewModel: HomeViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            rearrange
            logo
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .animation(.easeInOut, value: isEditingChains)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            address
        }
    }
    
    var rearrange: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral100)
            .frame(maxWidth: isEditingChains ? nil : 0)
            .clipped()
    }
    
    var header: some View {
        HStack(spacing: 12) {
            title
            Spacer()
            
            if group.coins.count > 1 {
                count
            } else {
                quantity
            }
            
            balance
        }
        .lineLimit(1)
    }
    
    var logo: some View {
        AsyncImageView(logo: group.logo, size: CGSize(width: 32, height: 32), ticker: group.chain.ticker, tokenChainLogo: group.chain.logo)
    }
    
    var title: some View {
        Text(group.name)
            .font(.body16MontserratBold)
            .foregroundColor(.neutral0)
    }
    
    var address: some View {
        Text(homeViewModel.hideVaultBalance ? "********************" : group.address)
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    
    var count: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : viewModel.getGroupCount(group))
            .font(.body12Menlo)
            .foregroundColor(.neutral100)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.blue400)
            .cornerRadius(50)
    }
    
    var quantity: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : group.nativeCoin.balanceString)
            .font(.body12Menlo)
            .foregroundColor(.neutral100)
    }
    
    var balance: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : group.totalBalanceInFiatString)
            .font(.body16MenloBold)
            .foregroundColor(.neutral100)
    }
}

#Preview {
    ScrollView {
        ChainCell(group: GroupedChain.example, isEditingChains: .constant(true))
            .environmentObject(HomeViewModel())
    }
}
