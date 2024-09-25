//
//  VaultDetailBalanceContent.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

struct VaultDetailBalanceContent: View {
    @ObservedObject var vault: Vault

    @State var width: CGFloat = .zero
    @State var redactedText = ""
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        container
            .onAppear {
                setData()
            }
    }
    
    var content: some View {
        ZStack {
            balanceContent
            hideButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.backgroundBlue)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    
    var balanceContent: some View {
        Text(homeViewModel.hideVaultBalance ? redactedText : (homeViewModel.selectedVault?.coins.totalBalanceInFiatString ?? ""))
            .font(.title32MenloBold)
            .foregroundColor(.neutral0)
            .padding(.top, 10)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

#Preview {
    VaultDetailBalanceContent(vault: Vault.example)
        .environmentObject(HomeViewModel())
}
