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

    @AppStorage("monthlyReminderDate") var monthlyReminderDate: Date = Date()
    @AppStorage("biweeklyPasswordVerifyDate") private var biweeklyPasswordVerifyDate: Double?

    @State var showSheet = false
    @State var isLoading = true
    @State var showScanner = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    @State var shouldSendCrypto = false

    @State var isSendLinkActive = false
    @State var isSwapLinkActive = false
    @State var isMemoLinkActive = false
    @State var isMonthlyBackupWarningLinkActive = false
    @State var isBiweeklyPasswordVerifyLinkActive = false
    @State var isBackupLinkActive = false
    @State var showUpgradeYourVaultSheet = false
    @State var upgradeYourVaultLinkActive = false
    @State var selectedChain: Chain? = nil

    @StateObject var sendTx = SendTransaction()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background()
            view
            scanButton
            popup
            shadowView
        }
        .sensoryFeedback(homeViewModel.showAlert ? .stop : .impact, trigger: homeViewModel.showAlert)
        .onAppear {
            appState.currentVault = homeViewModel.selectedVault
            onAppear()
        }
        .onChange(of: homeViewModel.selectedVault?.pubKeyECDSA) {
            if appState.currentVault?.pubKeyECDSA == homeViewModel.selectedVault?.pubKeyECDSA {
                return
            }
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
                vault: vault,
                coin: viewModel.selectedGroup?.nativeCoin
            )
        }
        .navigationDestination(isPresented: $isSwapLinkActive) {
            if let fromCoin = viewModel.selectedGroup?.nativeCoin {
                SwapCryptoView(fromCoin: fromCoin, vault: vault)
            }
        }
        .navigationDestination(isPresented: $isMemoLinkActive) {
            FunctionCallView(
                tx: sendTx,
                vault: vault,
                coin: viewModel.selectedGroup?.nativeCoin
            )
        }
        .navigationDestination(isPresented: $isBackupLinkActive) {
            BackupSetupView(tssType: .Keygen, vault: vault)
        }
        .navigationDestination(isPresented: $upgradeYourVaultLinkActive, destination: {
            if vault.isFastVault {
                VaultShareBackupsView(vault: vault)
            } else {
                AllDevicesUpgradeView(vault: vault)
            }
        })
        .sheet(isPresented: $showSheet, content: {
            NavigationView {
                ChainSelectionView(showChainSelectionSheet: $showSheet, vault: vault)
            }
        })
        .sheet(isPresented: $isMonthlyBackupWarningLinkActive) {
            MonthlyBackupView(isPresented: $isMonthlyBackupWarningLinkActive, isBackupPresented: $isBackupLinkActive)
                .presentationDetents([.height(224)])
        }
        .sheet(isPresented: $showUpgradeYourVaultSheet) {
            UpgradeYourVaultView(
                showSheet: $showUpgradeYourVaultSheet,
                navigationLinkActive: $upgradeYourVaultLinkActive
            )
        }
        .sheet(isPresented: $isBiweeklyPasswordVerifyLinkActive) {
            PasswordVerifyReminderView(vault: vault, isSheetPresented: $isBiweeklyPasswordVerifyLinkActive)
                .presentationDetents([.height(260)])
        }
    }

    var shadowView: some View {
        Background()
            .opacity(getBackgroundOpacity())
            .animation(.default, value: isMonthlyBackupWarningLinkActive)
            .animation(.default, value: isBiweeklyPasswordVerifyLinkActive)
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
    
    var chooseChainButtonLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
            Text(NSLocalizedString("chooseChains", comment: "Choose Chains"))
        }
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
    
    var popup: some View {
        PopupCapsule(
            text: homeViewModel.alertTitle,
            showPopup: $homeViewModel.showAlert
        )
    }
    
    var upgradeVaultBanner: some View {
        UpgradeFromGG20HomeBanner()
            .onTapGesture {
                showUpgradeYourVaultSheet = true
            }
    }
    
    private func onAppear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLoading = false
        }
        
        setData()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showMonthlyReminderIfNeeded()
            showBiweeklyPasswordVerificationIfNeeded()
        }
    }
    
    func setData() {
        
        if homeViewModel.selectedVault == nil {
            return
        }
        Task{
            viewModel.updateBalance(vault: vault)
            viewModel.getGroupAsync(tokenSelectionViewModel)
            
            tokenSelectionViewModel.setData(for: vault)
            settingsDefaultChainViewModel.setData(tokenSelectionViewModel.groupedAssets)
            viewModel.categorizeCoins(vault: vault)
        }
    }
    
    func getActions() -> some View {
        let selectedGroup = viewModel.selectedGroup
        
        return ChainDetailActionButtons(
            isChainDetail:false,
            group: selectedGroup ?? GroupedChain.example,
            isLoading: $isLoading,
            isSendLinkActive: $isSendLinkActive,
            isSwapLinkActive: $isSwapLinkActive,
            isMemoLinkActive: $isMemoLinkActive
        )
        .padding(16)
        .padding(.horizontal, 12)
        .redacted(reason: selectedGroup == nil ? .placeholder : [])
        .background(Color.backgroundBlue)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private func showMonthlyReminderIfNeeded() {
        let diff = Calendar.current.dateComponents([.day], from: monthlyReminderDate, to: Date())

        if let days = diff.day, days >= 30 {
            isMonthlyBackupWarningLinkActive = true
        }
    }
    
    private func showBiweeklyPasswordVerificationIfNeeded() {
        guard vault.isFastVault else { return }
        
        guard let lastVerifyTimestamp = biweeklyPasswordVerifyDate else {
            return
        }
        
        let lastVerifyDate = Date(timeIntervalSince1970: lastVerifyTimestamp)
        let currentDate = Date()
        
        let calendar = Calendar.current
        let difference = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastVerifyDate), to: calendar.startOfDay(for: currentDate))
        
        if let days = difference.day, days >= 15 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isBiweeklyPasswordVerifyLinkActive = true
            }
        }
    }
    
    func getBackgroundOpacity() -> CGFloat {
        if isMonthlyBackupWarningLinkActive || isBiweeklyPasswordVerifyLinkActive {
            0.5
        } else {
            0
        }
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
