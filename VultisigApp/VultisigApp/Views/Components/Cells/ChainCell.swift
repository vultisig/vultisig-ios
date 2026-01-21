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
        .background(Theme.colors.bgSurface1)
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
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
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
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var address: some View {
        Text(homeViewModel.hideVaultBalance ? "********************" : group.address)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.bgButtonPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    var count: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : viewModel.getGroupCount(group))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.colors.bgSurface2)
            .cornerRadius(50)
    }

    var quantity: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : group.nativeCoin.balanceString)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var balance: some View {
        Text(homeViewModel.hideVaultBalance ? "****" : group.totalBalanceInFiatString)
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }
}

#Preview {
    ScrollView {
        ChainCell(group: GroupedChain.example, isEditingChains: .constant(true))
            .environmentObject(HomeViewModel())
    }
}
