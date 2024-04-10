//
//  ChainDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-10.
//

import SwiftUI

struct ChainDetailView: View {
    let title: String
    let group: GroupedChain
    let vault: Vault
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(title, comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton()
            }
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 20) {
                actions
                content
                chooseTokensButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 30)
        }
    }
    
    var actions: some View {
        HStack(spacing: 12) {
            sendButton
            swapButton
            
            if group.name == "THORChain" {
                depositButton
            }
        }
    }
    
    var sendButton: some View {
        NavigationLink {
//            SendCryptoView(
//                tx: sendTx,
//                coinViewModel: coinViewModel,
//                group: group,
//                vault: vault
//            )
        } label: {
            getButton(for: "send", with: .turquoise600)
        }
    }
    
    var swapButton: some View {
        getButton(for: "swap", with: .persianBlue200)
    }
    
    var depositButton: some View {
        getButton(for: "deposit", with: .mediumPurple)
    }
    
    var content: some View {
        VStack(spacing: 0) {
            header
            cells
        }
        .cornerRadius(10)
    }
    
    var header: some View {
        ChainHeaderCell(group: group)
    }
    
    var cells: some View {
        ForEach(group.coins, id: \.self) { coin in
            VStack(spacing: 0) {
                Separator()
                CoinCell(coin: coin, group: group, vault: vault)
            }
        }
    }
    
    var chooseTokensButton: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
            Text(NSLocalizedString("chooseTokens", comment: "Choose Tokens"))
            Spacer()
        }
        .font(.body16MenloBold)
        .foregroundColor(.turquoise600)
    }
    
    private func getButton(for title: String, with color: Color) -> some View {
        Text(NSLocalizedString(title, comment: "").uppercased())
            .font(.body16MenloBold)
            .foregroundColor(color)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Color.blue400)
            .cornerRadius(50)
    }
}

#Preview {
    ChainDetailView(title: "Ethereum", group: GroupedChain.example, vault: Vault.example)
}
