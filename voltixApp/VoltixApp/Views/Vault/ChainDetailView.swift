//
//  ChainDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-10.
//

import SwiftUI

struct ChainDetailView: View {
    let group: GroupedChain
    let vault: Vault
    let balanceInFiat: String?
    
    @State var showSheet = false
    @State var tokens: [Coin] = []
    @State var actions: [CoinAction] = []

    @StateObject var sendTx = SendTransaction()
    
    @EnvironmentObject var viewModel: TokenSelectionViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString(group.name, comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton()
            }
        }
        .sheet(isPresented: $showSheet, content: {
            NavigationView {
                TokenSelectionView(
                    showTokenSelectionSheet: $showSheet,
                    vault: vault,
                    group: group,
                    tokens: tokens
                )
            }
        })
        .onAppear {
            Task {
                await setData()
            }
        }
        .onChange(of: vault) {
            Task {
                await setData()
            }
        }
    }
    
    var view: some View {
        ScrollView {
            VStack(spacing: 20) {
                actionButtons
                content
                
                if tokens.count>0 {
                    addButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 30)
        }
    }

    @ViewBuilder
    var actionButtons: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.rawValue) { action in
                switch action {
                case .send:
                    sendButton
                case .swap:
                    swapButton
                case .deposit, .custom:
                    getButton(for: action.title, with: action.color)
                }
            }
        }
        .frame(height: 28)
    }

    var sendButton: some View {
        NavigationLink {
            SendCryptoView(
                tx: sendTx,
                group: group,
                vault: vault
            )
        } label: {
            ActionButton(title: "send", fontColor: .turquoise600)
        }
    }
    
    var swapButton: some View {
        NavigationLink {
            if let coin = group.coins.first {
                SwapCryptoView(coin: coin, coins: viewModel.allCoins, vault: vault)
            }
        } label: {
            ActionButton(title: "swap", fontColor: .persianBlue200)
        }
    }
    
    var depositButton: some View {
        ActionButton(title: "deposit", fontColor: .mediumPurple)
    }
    
    var content: some View {
        VStack(spacing: 0) {
            header
            cells
        }
        .cornerRadius(10)
    }
    
    var header: some View {
        ChainHeaderCell(group: group, balanceInFiat: balanceInFiat)
    }
    
    var cells: some View {
        ForEach(group.coins, id: \.self) { coin in
            VStack(spacing: 0) {
                Separator()
                CoinCell(coin: coin, group: group, vault: vault)
            }
        }
    }
    
    var addButton: some View {
        Button {
            showSheet.toggle()
        } label: {
            chooseTokensButton
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
    
    private func setData() async {
        viewModel.setData(for: vault)
        tokens = viewModel.groupedAssets[group.name] ?? []
        tokens.removeFirst()

        actions = await viewModel.actionResolver.resolveActions(for: group.chain)

        if let coin = group.coins.first {
            sendTx.reset(coin: coin)
        }
    }
}

#Preview {
    ChainDetailView(group: GroupedChain.example, vault: Vault.example, balanceInFiat: "$65,899")
        .environmentObject(TokenSelectionViewModel())
}
