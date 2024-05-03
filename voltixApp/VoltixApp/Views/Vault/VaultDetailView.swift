//
//
//  VaultDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI

struct VaultDetailView: View {
    @Binding var showVaultsList: Bool
    let vault: Vault
    
    @EnvironmentObject var appState: ApplicationState
    @EnvironmentObject var viewModel: VaultDetailViewModel
    
    @State var showSheet = false
    @State var totalBalance: Decimal = 0
    @State var totalUpdateCount: Int = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
            scanButton
        }
        .onAppear {
            setData()
            appState.currentVault = vault
			ApplicationState.shared.currentVault = vault
        }
        .onChange(of: vault) {
            setData()
        }
        .onChange(of: vault.coins) {
            setData()
        }
        .sheet(isPresented: $showSheet, content: {
            NavigationView {
                ChainSelectionView(showChainSelectionSheet: $showSheet, vault: vault)
            }
        })
    }
    
    var view: some View {
        ScrollView {
            if viewModel.coinsGroupedByChains.count>1 {
                list
            } else {
                emptyList
            }
            
            addButton
        }
        .opacity(showVaultsList ? 0 : 1)
    }
    
    var list: some View {
        VStack(spacing: 16) {
            balanceContent
            chainList
        }
        .padding(.top, 30)
    }
    
    var emptyList: some View {
        ErrorMessage(text: "noChainSelected")
            .padding(.vertical, 50)
    }
    
    var balanceContent: some View {
        Text(totalBalance.formatToFiat())
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .redacted(reason: totalUpdateCount>=viewModel.coinsGroupedByChains.count ? [] : .placeholder)
    }
    
    var chainList: some View {
        ForEach(viewModel.coinsGroupedByChains, id: \.id) { group in
            ChainNavigationCell(
                group: group,
                vault: vault,
                totalBalance: $totalBalance,
                totalUpdateCount: $totalUpdateCount
            )
        }
    }
    
    var addButton: some View {
        Button {
            showSheet.toggle()
        } label: {
            chooseChainButton
        }
        .padding(16)
        .padding(.bottom, 150)
    }
    
    var chooseChainButton: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
            Text(NSLocalizedString("chooseChains", comment: "Choose Chains"))
            Spacer()
        }
        .font(.body16MenloBold)
        .foregroundColor(.turquoise600)
    }
       
    var scanButton: some View {
        NavigationLink {
            JoinKeysignView(vault: vault)
        } label: {
            ZStack {
                Circle()
                    .foregroundColor(.blue800)
                    .frame(width: 80, height: 80)
                    .opacity(0.8)
                
                Circle()
                    .foregroundColor(.turquoise600)
                    .frame(width: 60, height: 60)
                
                Image(systemName: "camera")
                    .font(.title30MenloUltraLight)
                    .foregroundColor(.blue600)
            }
            .opacity(showVaultsList ? 0 : 1)
        }
    }
    
    private func setData() {
        totalBalance = 0
        totalUpdateCount = 0
        viewModel.fetchCoins(for: vault)
    }
}

#Preview {
    VaultDetailView(showVaultsList: .constant(false), vault: Vault.example)
        .environmentObject(VaultDetailViewModel())
        .environmentObject(ApplicationState.shared)
}
