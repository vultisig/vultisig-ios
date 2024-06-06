//
//
//  VaultDetailView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI

struct VaultDetailView: View {
    @Binding var showVaultsList: Bool
    let vault: Vault
    
    @EnvironmentObject var appState: ApplicationState
    @EnvironmentObject var viewModel: VaultDetailViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var tokenSelectionViewModel: CoinSelectionViewModel
    
    @State var showSheet = false
    @State var isLoading = true
    @State var showScanner = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    @StateObject var sendTx = SendTransaction()

    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
            scanButton
        }
        .onAppear {
            appState.currentVault = homeViewModel.selectedVault
            onAppear()
        }
        .onChange(of: homeViewModel.selectedVault?.pubKeyECDSA) {
            print("on vault Pubkey change \(homeViewModel.selectedVault?.pubKeyECDSA ?? "")")
            appState.currentVault = homeViewModel.selectedVault
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
        list
        .opacity(showVaultsList ? 0 : 1)
        .sheet(isPresented: $showScanner, content: {
            GeneralCodeScannerView(
                showSheet: $showScanner,
                shouldJoinKeygen: $shouldJoinKeygen,
                shouldKeysignTransaction: $shouldKeysignTransaction
            )
        })
        .navigationDestination(isPresented: $shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"))
        }
        .navigationDestination(isPresented: $shouldKeysignTransaction) {
            if let vault = homeViewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
    }
    
    var list: some View {
        List {
            if isLoading {
                loader
            } else if viewModel.coinsGroupedByChains.count>=1 {
                balanceContent
                getActions()
                cells
            } else {
                emptyList
            }
            
            addButton
        }
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
        .background(Color.backgroundBlue)
        .refreshable {
            viewModel.updateBalance()
        }
        .colorScheme(.dark)
    }
    
    var cells: some View {
        ForEach(viewModel.coinsGroupedByChains.sorted(by: {
            $0.coins.totalBalanceInFiatDecimal > $1.coins.totalBalanceInFiatDecimal
        }), id: \.id) { group in
            ChainNavigationCell(
                group: group,
                vault: vault
            )
        }
        .background(Color.backgroundBlue)
    }
    
    var emptyList: some View {
        ErrorMessage(text: "noChainSelected")
            .padding(.vertical, 50)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .background(Color.backgroundBlue)
    }
    
    var balanceContent: some View {
        Text(vault.coins.totalBalanceInFiatString)
            .font(.title32MenloBold)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .background(Color.backgroundBlue)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .multilineTextAlignment(.center)
    }
    
    var chainList: some View {
        ForEach(viewModel.coinsGroupedByChains, id: \.id) { group in
            ChainNavigationCell(group: group, vault: vault)
        }
    }
    
    var addButton: some View {
        HStack {
            chooseChainButton
            Spacer()
        }
        .padding(16)
        .padding(.bottom, 150)
        .background(Color.backgroundBlue)
        .background(Color.backgroundBlue)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    
    var chooseChainButton: some View {
        Button {
            showSheet.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                Text(NSLocalizedString("chooseChains", comment: "Choose Chains"))
            }
        }
        .font(.body16MenloBold)
        .foregroundColor(.turquoise600)
    }
       
    var scanButton: some View {
        VaultDetailScanButton(showSheet: $showScanner)
            .opacity(showVaultsList ? 0 : 1)
    }
    
    var loader: some View {
        HStack(spacing: 20) {
            Text(NSLocalizedString("fetchingVaultDetails", comment: ""))
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
            
            ProgressView()
                .preferredColorScheme(.dark)
        }
        .padding(.vertical, 50)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .background(Color.backgroundBlue)
    }
    
    private func onAppear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLoading = false
        }
        setData()
    }
    
    private func setData() {
        viewModel.fetchCoins(for: vault)
        viewModel.setOrder()
        viewModel.updateBalance()
        viewModel.getGroupAsync(tokenSelectionViewModel)
    }
    
    private func getListHeight() -> CGFloat {
        CGFloat(viewModel.coinsGroupedByChains.count*86)
    }
    
    private func getActions() -> some View {
        let selectedGroup = viewModel.selectedGroup
        
        return ChainDetailActionButtons(group: selectedGroup ?? GroupedChain.example, vault: vault, sendTx: sendTx)
            .padding(16)
            .padding(.horizontal, 12)
            .redacted(reason: selectedGroup == nil ? .placeholder : [])
            .background(Color.backgroundBlue)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
}

#Preview {
    VaultDetailView(showVaultsList: .constant(false), vault: Vault.example)
        .environmentObject(ApplicationState())
        .environmentObject(VaultDetailViewModel())
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
