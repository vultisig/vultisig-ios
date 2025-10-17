//
//  HomeScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI
import SwiftData

struct HomeScreen: View {
    let initialVault: Vault?
    let showingVaultSelector: Bool
    
    @State var selectedVault: Vault? = nil
    @State var showVaultSelector: Bool = false
    @State var addressToCopy: Coin?
    @State var showUpgradeVaultSheet: Bool = false
    
    @State var vaults: [Vault] = []
    @State private var selectedTab: HomeTab = .wallet
    @State var vaultRoute: VaultMainRoute?
    
    // Properties for QR Code scanner
    @State var showScanner: Bool = false
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    @State var shouldSendCrypto = false
    @State var shouldImportBackup = false
    @State var showBackupNow = false
    @StateObject var sendTx = SendTransaction()
    @State var selectedChain: Chain? = nil
    
    @State var walletShowPortfolioHeader: Bool = false
    @State var defiShowPortfolioHeader: Bool = false
    @State var showPortfolioHeader: Bool = false
    
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var phoneCheckUpdateViewModel: PhoneCheckUpdateViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @Environment(\.modelContext) private var modelContext
    
    init(initialVault: Vault? = nil, showingVaultSelector: Bool = false) {
        self.initialVault = initialVault
        self.showingVaultSelector = showingVaultSelector
    }
    
    var body: some View {
        ZStack {
            if let selectedVault = homeViewModel.selectedVault {
                content(selectedVault: selectedVault)
            } else {
                initialView
            }
        }
        .onLoad {
            setData()
            showVaultSelector = showingVaultSelector
        }
        .alert(
            NSLocalizedString("newUpdateAvailable", comment: ""),
            isPresented: $phoneCheckUpdateViewModel.showUpdateAlert
        ) {
            Link(destination: StaticURL.AppStoreVultisigURL) {
                Text(NSLocalizedString("updateNow", comment: ""))
            }
            
            Button(NSLocalizedString("dismiss", comment: ""), role: .cancel) {}
        } message: {
            Text(phoneCheckUpdateViewModel.latestVersionString)
        }
    }
    
    var initialView: some View {
        VaultMainScreenBackground()
            .ignoresSafeArea()
    }
    
    func content(selectedVault: Vault) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VultiTabBar(
                    selectedItem: $selectedTab,
                    items: [HomeTab.wallet, .defi],
                    accessory: .camera,
                ) { tab in
                    Group {
                        switch tab {
                        case .wallet:
                            VaultMainScreen(
                                vault: selectedVault,
                                routeToPresent: $vaultRoute,
                                addressToCopy: $addressToCopy,
                                showUpgradeVaultSheet: $showUpgradeVaultSheet,
                                showBackupNow: $showBackupNow,
                                showBalanceInHeader: $walletShowPortfolioHeader
                            )
                        case .defi:
                            DefiMainScreen(
                                vault: selectedVault,
                                showBalanceInHeader: $defiShowPortfolioHeader
                            )
                        case .camera:
                            EmptyView()
                        }
                    }
#if os(macOS)
                    .navigationBarBackButtonHidden()
#endif
                } onAccessory: {
                    onCamera()
                }
                
                header(vault: selectedVault)
            }
            .sensoryFeedback(homeViewModel.showAlert ? .stop : .impact, trigger: homeViewModel.showAlert)
            .customNavigationBarHidden(true)
            .withAddressCopy(coin: $addressToCopy)
            .withUpgradeVault(vault: selectedVault, shouldShow: $showUpgradeVaultSheet)
            .withBiweeklyPasswordVerification(vault: selectedVault)
            .withMonthlyBackupWarning(vault: selectedVault)
            .onLoad {
                onVaultLoaded(vault: selectedVault)
            }
            .onChange(of: walletShowPortfolioHeader) { _,_ in updateHeader() }
            .onChange(of: defiShowPortfolioHeader) { _,_ in updateHeader() }
            .onChange(of: selectedTab) { oldValue, newValue in
                updateHeader()
                if newValue == .camera {
                    selectedTab = oldValue
                    onCamera()
                }
            }
            .navigationDestination(item: $vaultRoute) {
                buildVaultRoute(route: $0, vault: selectedVault)
            }
#if os(macOS)
            .navigationDestination(isPresented: $showScanner) {
                MacScannerView(type: .SignTransaction, sendTx: sendTx, selectedVault: selectedVault)
            }
#else
            .crossPlatformSheet(isPresented: $showScanner) {
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    GeneralQRImportMacView(type: .SignTransaction, sendTx: sendTx, selectedVault: selectedVault)
                } else {
                    GeneralCodeScannerView(
                        showSheet: $showScanner,
                        shouldJoinKeygen: $shouldJoinKeygen,
                        shouldKeysignTransaction: $shouldKeysignTransaction,
                        shouldSendCrypto: $shouldSendCrypto,
                        selectedChain: $selectedChain,
                        sendTX: sendTx
                    )
                }
            }
#endif
            .navigationDestination(isPresented: $shouldJoinKeygen) {
                JoinKeygenView(vault: Vault(name: "Main Vault"), selectedVault: selectedVault)
            }
            .onChange(of: shouldSendCrypto) { _, newValue in
                guard newValue else { return }
                shouldSendCrypto = false
                let deeplinkChain = selectedVault.coins.first(where: { $0.isNativeToken && selectedChain == $0.chain })
                vaultRoute = .mainAction(.send(coin: deeplinkChain ?? vaultDetailViewModel.selectedGroup?.nativeCoin, hasPreselectedCoin: false))
            }
            .navigationDestination(isPresented: $shouldKeysignTransaction) {
                if let vault = homeViewModel.selectedVault {
                    JoinKeysignView(vault: vault)
                }
            }
            .navigationDestination(isPresented: $shouldImportBackup) {
                ImportWalletView()
            }
            .navigationDestination(isPresented: $showBackupNow) {
                if let vault = homeViewModel.selectedVault {
                    VaultBackupNowScreen(tssType: .Keygen, backupType: .single(vault: vault))
                }
            }
            .crossPlatformSheet(isPresented: $showVaultSelector) {
                VaultManagementSheet(availableHeight: geo.size.height) {
                    showVaultSelector.toggle()
                    vaultRoute = .createVault
                } onSelectVault: { vault in
                    showVaultSelector.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        homeViewModel.setSelectedVault(vault)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func header(vault: Vault) -> some View {
        HomeMainHeaderView(
            vault: vault,
            activeTab: $selectedTab,
            showBalance: $showPortfolioHeader,
            vaultSelectorAction: { showVaultSelector.toggle() },
            settingsAction: { vaultRoute = .settings },
            onRefresh: {}
        )
    }
}

private extension HomeScreen {
    func updateHeader() {
        let showOpaqueHeader: Bool
        switch selectedTab {
        case .defi:
            showOpaqueHeader = defiShowPortfolioHeader
        case .wallet:
            showOpaqueHeader = walletShowPortfolioHeader
        case .camera:
            return
        }
        
        self.showPortfolioHeader = showOpaqueHeader
    }
    
    func moveToVaultsView() {
        guard let vault = deeplinkViewModel.selectedVault else {
            return
        }
        
        homeViewModel.setSelectedVault(vault)
        showVaultSelector = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            shouldKeysignTransaction = true
        }
    }
    
    func checkUpdate() {
        phoneCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
    }
    
    func moveToCreateVaultView() {
        showVaultSelector = false
        shouldJoinKeygen = true
    }
    
    func onCamera() {
        showScanner = true
    }
    
    func fetchVaults() {
        var fetchVaultDescriptor = FetchDescriptor<Vault>()
        fetchVaultDescriptor.relationshipKeyPathsForPrefetching = [\.coins, \.hiddenTokens, \.referralCode, \.referredCode]
        do {
            vaults = try modelContext.fetch(fetchVaultDescriptor)
        } catch {
            print(error)
        }
    }
    
    func setData() {
        fetchVaults()
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        homeViewModel.selectedVault = nil
        checkUpdate()
        
        if let vault = initialVault {
            homeViewModel.setSelectedVault(vault)
            selectedVault = nil
            return
        } else {
            homeViewModel.loadSelectedVault(for: vaults)
        }
        
        presetValuesForDeeplink()
    }
    
    func presetValuesForDeeplink() {
        if let _ = vultExtensionViewModel.documentData {
            shouldImportBackup = true
        }
        
        guard let type = deeplinkViewModel.type else {
            return
        }
        deeplinkViewModel.type = nil
        
        switch type {
        case .NewVault:
            moveToCreateVaultView()
        case .SignTransaction:
            moveToVaultsView()
        case .Unknown:
            return
        }
    }
    
    func onVaultLoaded(vault: Vault) {
        // Enable chains for Defi tab if needed, only once per vault lifecycle
        Task { @MainActor in
            await VaultDefiChainsService().enableDefiChainsIfNeeded(for: vault)
        }
    }
}

extension HomeScreen {
    @ViewBuilder
    func buildVaultRoute(route: VaultMainRoute, vault: Vault) -> some View {
        switch route {
        case .settings:
            SettingsMainScreen(vault: vault)
        case .createVault:
            CreateVaultView(selectedVault: selectedVault, showBackButton: true)
        case .mainAction(let action):
            VaultActionRouteBuilder().buildActionRoute(action: action, sendTx: sendTx, vault: vault)
        }
    }
}

#Preview {
    HomeScreen(initialVault: .example, showingVaultSelector: false)
        .environmentObject(HomeViewModel())
        .environmentObject(VaultDetailViewModel())
}
