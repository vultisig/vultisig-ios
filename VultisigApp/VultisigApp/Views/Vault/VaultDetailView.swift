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
    @ObservedObject var vault: Vault
    
    @EnvironmentObject var appState: ApplicationState
    @EnvironmentObject var viewModel: VaultDetailViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var tokenSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    
    @State var showSheet = false
    @State var isLoading = true
    @State var showScanner = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    @State var shouldSendCrypto = false

    @State var isSendLinkActive = false
    @State var isSwapLinkActive = false
    @State var isMemoLinkActive = false
    @State var showAlert: Bool = false
    @State var selectedChain: Chain? = nil

    @StateObject var sendTx = SendTransaction()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
            scanButton
            PopupCapsule(text: "addressCopied", showPopup: $showAlert)
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
        .onChange(of: homeViewModel.selectedVault?.coins) {
            setData()
        }
        .navigationDestination(isPresented: $isSendLinkActive) {
            SendCryptoView(
                tx: sendTx,
                vault: vault
            )
        }
        .navigationDestination(isPresented: $isSwapLinkActive) {
            if let fromCoin = viewModel.selectedGroup?.nativeCoin {
                SwapCryptoView(fromCoin: fromCoin, vault: vault)
            }
        }
        .navigationDestination(isPresented: $isMemoLinkActive) {
            TransactionMemoView(
                tx: sendTx,
                vault: vault
            )
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
                    shouldKeysignTransaction: $shouldKeysignTransaction, 
                    shouldSendCrypto: $shouldSendCrypto,
                    selectedChain: $selectedChain, 
                    sendTX: sendTx
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
            .navigationDestination(isPresented: $shouldSendCrypto) {
                SendCryptoView(
                    tx: sendTx,
                    vault: vault,
                    selectedChain: selectedChain
                )
            }
    }
    
    var list: some View {
        List {
            if isLoading {
                loader
            } else if viewModel.coinsGroupedByChains.count >= 1 {
                
                if !vault.isBackedUp {
                    backupNowWidget
                }
                
                balanceContent
                getActions()
                cells
            } else {
                emptyList
            }
            
            addButton
            pad
        }
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
        .refreshable {
            viewModel.updateBalance(vault: vault)
        }
        .colorScheme(.dark)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundBlue)
    }
    
    var cells: some View {
        let sortedGroups = viewModel.coinsGroupedByChains.sorted(by: {
            $0.totalBalanceInFiatDecimal > $1.totalBalanceInFiatDecimal
        })
        
        return ForEach(sortedGroups, id: \.id) { group in
            ChainNavigationCell(
                group: group,
                vault: vault, 
                showAlert: $showAlert
            )
        }
        .background(Color.backgroundBlue)
#if os(macOS)
        .padding(.horizontal, 16)
#endif
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
        VaultDetailBalanceContent(vault: vault)
    }
    
    var addButton: some View {
        HStack {
            chooseChainButton
            Spacer()
        }
        .padding(16)
        .background(Color.backgroundBlue)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    
    var pad: some View {
        Color.backgroundBlue
            .frame(height: 150)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
    
    var chooseChainButton: some View {
        ZStack {
#if os(iOS)
            Button {
                showSheet.toggle()
            } label: {
                chooseChainButtonLabel
            }
#elseif os(macOS)
            NavigationLink {
                ChainSelectionView(showChainSelectionSheet: $showSheet, vault: vault)
            } label: {
                chooseChainButtonLabel
            }
            .padding(.horizontal, 16)
            .frame(height: 20)
#endif
        }
        .font(.body16MenloBold)
        .foregroundColor(.turquoise600)
    }
    
    var chooseChainButtonLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
            Text(NSLocalizedString("chooseChains", comment: "Choose Chains"))
        }
    }
    
    var scanButton: some View {
        VaultDetailScanButton(showSheet: $showScanner)
            .opacity(showVaultsList ? 0 : 1)
            .buttonStyle(BorderlessButtonStyle())
#if os(macOS)
            .padding(.bottom, 30)
#endif
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
    
    var backupNowWidget: some View {
        BackupNowDisclaimer(vault: vault)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .background(Color.backgroundBlue)
    }
    
    private func onAppear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLoading = false
        }
        setData()
    }
    
    private func setData() {
        if homeViewModel.selectedVault == nil {
            return
        }
        viewModel.fetchCoins(for: vault)
        viewModel.setOrder()
        viewModel.updateBalance(vault: vault)
        viewModel.getGroupAsync(tokenSelectionViewModel)
        
        tokenSelectionViewModel.setData(for: vault)
        settingsDefaultChainViewModel.setData(tokenSelectionViewModel.groupedAssets)
    }
    
    private func getListHeight() -> CGFloat {
        CGFloat(viewModel.coinsGroupedByChains.count * 86)
    }
    
    private func getActions() -> some View {
        let selectedGroup = viewModel.selectedGroup
        
        return ChainDetailActionButtons(group: selectedGroup ?? GroupedChain.example, sendTx: sendTx, isSendLinkActive: $isSendLinkActive, isSwapLinkActive: $isSwapLinkActive, isMemoLinkActive: $isMemoLinkActive)
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
        .environmentObject(SettingsDefaultChainViewModel())
}
