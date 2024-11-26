//
//  ChainHeaderCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-26.
//

import SwiftUI


struct ChainHeaderCell: View {
    let vault: Vault
    @ObservedObject var group: GroupedChain
    @Binding var isLoading: Bool
    @Binding var showAlert: Bool
    
    @State var showQRcode = false
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        cell
            .sheet(isPresented: $showQRcode) {
                NavigationView {
                    AddressQRCodeView(
                        addressData: group.address, 
                        vault: vault, 
                        groupedChain: group,
                        showSheet: $showQRcode,
                        isLoading: $isLoading
                    )
                }
            }
    }
    
    var cell: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .background(Color.blue600)
    }
    
    var logo: some View {
        AsyncImageView(logo: group.logo, size: CGSize(width: 32, height: 32), ticker: group.chain.ticker, tokenChainLogo: group.chain.logo)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            fiatBalance
            address
        }
    }
    
    var header: some View {
        HStack(spacing: 12) {
            logo
            title
            Spacer()
            actions
        }
    }
    
    var title: some View {
        Text(group.name.capitalized)
            .font(.body20MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var actions: some View {
        HStack(spacing: 12) {
            copyButton
            showQRButton
            showTransactionsButton
        }
    }
    
    var fiatBalance: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : group.totalBalanceInFiatString)
            .font(.body20MenloBold)
            .foregroundColor(.neutral0)
    }
    
    var copyButton: some View {
        Button {
            copyAddress()
        } label: {
            Image(systemName: "square.on.square")
                .foregroundColor(.neutral0)
                .font(.body18MenloMedium)
        }
    }
    
    var qrCodeLabel: some View {
        Image(systemName: "qrcode")
            .foregroundColor(.neutral0)
            .font(.body18MenloMedium)
    }
    
    var showTransactionsButton: some View {
        webLink
    }
    
    var transactionsViewLink: some View {
        NavigationLink {
            TransactionsView(group: group)
        } label: {
            Image(systemName: "cube")
                .foregroundColor(.neutral0)
                .font(.body18MenloMedium)
        }
    }
    
    var webLink: some View {
        ZStack {
            if let url = Endpoint.getExplorerByAddressURLByGroup(chain: group.coins.first?.chain, address: group.address),
               let linkURL = URL(string: url) {
                Link(destination: linkURL) {
                    Image(systemName: "cube")
                        .foregroundColor(.neutral0)
                        .font(.body18MenloMedium)
                }
            } else {
                EmptyView()
            }
        }
    }
    
    var address: some View {
        Text(homeViewModel.hideVaultBalance ? "********************" : group.address)
            .font(.body12Menlo)
            .foregroundColor(.turquoise600)
            .lineLimit(1)
    }
}

#Preview {
    ChainHeaderCell(
        vault: Vault.example,
        group: GroupedChain.example,
        isLoading: .constant(false),
        showAlert: .constant(false)
    )
}
