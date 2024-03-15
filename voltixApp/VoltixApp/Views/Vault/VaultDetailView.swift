//
//  VaultDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI

struct VaultDetailView: View {
    @Binding var presentationStack: [CurrentScreen]
    @Binding var showVaultsList: Bool
    @EnvironmentObject var appState: ApplicationState
    let vault: Vault
    
    @EnvironmentObject var viewModel: VaultDetailViewModel
    @State var showSheet = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            background
            view
            scanButton
        }
        .onAppear {
            setData()
            appState.currentVault = vault
        }
        .onChange(of: vault) {
            setData()
        }
        .onChange(of: vault.coins) {
            setData()
        }
        .sheet(isPresented: $showSheet, content: {
            NavigationView {
                TokenSelectionView(showTokenSelectionSheet: $showSheet, vault: vault)
            }
        })
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        ScrollView {
            list
            addButton
            testButton
        }
        .opacity(showVaultsList ? 0 : 1)
    }
    
    var list: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.coinsGroupedByChains, id: \.address) { group in
                ChainCell(group: group)
            }
        }
        .padding(.top, 30)
    }
    
    var addButton: some View {
        Button {
            showSheet.toggle()
        } label: {
            FilledButton(title: "chooseTokens", icon: "plus")
        }
        .padding(16)
        .padding(.bottom, 150)
    }
    
    var testButton: some View {
        NavigationLink {
            KeysignDiscoveryView(vault: vault, keysignPayload: KeysignPayload(
                coin: vault.coins.first{$0.ticker == "LTC"}!,
                toAddress: "ltc1q4c3y3acddm4n22uk2rrekq2wrczqq7mg2cy99w",
                toAmount: 2000000, //
                chainSpecific: BlockChainSpecific.UTXO(byteFee: 10),
                utxos: [
                    UtxoInfo(hash: "ffb6117cd1a8502baca498da9ff3ce1e49fd6386f5c7aa52e7f6456a1255eb74", amount: 50000000, index: 0)
                ],
                memo: "",
                swapPayload: nil))
        } label: {
            FilledButton(title: "test")
        }
        .padding(16)
        .padding(.bottom, 150)
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
        viewModel.fetchCoins(for: vault)
    }
}

#Preview {
    VaultDetailView(presentationStack: .constant([]), showVaultsList: .constant(false), vault: Vault.example)
        .environmentObject(VaultDetailViewModel())
}
