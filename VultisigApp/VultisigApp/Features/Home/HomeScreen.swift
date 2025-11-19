//
//  HomeScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI
import SwiftData
import WalletCore

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
    @State var shouldRefresh: Bool = false
    
    // Capture geometry height to avoid circular layout dependency during sheet presentation
    @State private var capturedGeometryHeight: CGFloat = 600
    
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var phoneCheckUpdateViewModel: PhoneCheckUpdateViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @Environment(\.modelContext) private var modelContext
    private let tabs: [HomeTab] = [.wallet, .defi]

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
        .onAppear {
            // CRITICAL: Process pending deeplink if app was opened via deeplink
            // This handles the case when app is closed and opened via QR code
            // The deeplink may have been processed before HomeScreen was in view hierarchy
            if deeplinkViewModel.type != nil {
                // Wait for vaults to be loaded (setData is called in onLoad)
                // Use a longer delay to ensure setData has completed
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // Only process if type is still set and vaults are loaded
                    if deeplinkViewModel.type != nil {
                        presetValuesForDeeplink()
                    }
                }
            }
        }
        .onLoad {
            // FIXED: Set initial state BEFORE loading data to avoid overwriting changes made by setData()
            showVaultSelector = showingVaultSelector
            
            setData()
            
            // CRITICAL: Process pending deeplink if app was opened via deeplink
            // This handles the case when app is closed and opened via QR code
            // The deeplink may have been processed before HomeScreen was in view hierarchy
            // NOTE: setData() already calls presetValuesForDeeplink() at the end,
            // but we add this as a backup in case setData doesn't process it
            if deeplinkViewModel.type != nil {
                
                // Wait for setData to complete and vaults to be loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    
                    // Only process if type is still set (setData might have already processed it)
                    if deeplinkViewModel.type != nil {
                        presetValuesForDeeplink()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ProcessDeeplink"))) { _ in
            
            // If scanner is open and this is a Send deeplink, close scanner first
            if showScanner && deeplinkViewModel.type == .Send {
                showScanner = false
                
                // Wait for scanner to close, then process deeplink
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    presetValuesForDeeplink()
                }
            } else {
                presetValuesForDeeplink()
            }
        }
        .onChange(of: deeplinkViewModel.type) { oldValue, newValue in
            // Process deeplink when type changes (e.g., when app is already open and QR code is scanned)
            if newValue != nil {
                presetValuesForDeeplink()
            }
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
            let mainContent = buildMainContent(selectedVault: selectedVault)
            return applyModifiers(to: mainContent, selectedVault: selectedVault, geo: geo)
        }
    }
    
    @ViewBuilder
    private func buildMainContent(selectedVault: Vault) -> some View {
        ZStack(alignment: .top) {
            VultiTabBar(
                selectedItem: $selectedTab,
                items: tabs,
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
                            showBalanceInHeader: $walletShowPortfolioHeader,
                            shouldRefresh: $shouldRefresh
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
    }
    
    @ViewBuilder
    private func applyModifiers<V: View>(to view: V, selectedVault: Vault, geo: GeometryProxy) -> some View {
        let withBasicModifiers = view
            .onAppear {
                // Capture geometry height to avoid circular layout dependency
                capturedGeometryHeight = geo.size.height
            }
            .onChange(of: geo.size.height) { _, newHeight in
                // Update captured height when geometry changes (but not during sheet presentation)
                if !showVaultSelector {
                    capturedGeometryHeight = newHeight
                }
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
            .navigationDestination(item: $vaultRoute) { route in
                buildVaultRoute(route: route, vault: selectedVault)
            }
        
        return applyNavigationModifiers(to: withBasicModifiers, selectedVault: selectedVault)
    }
    
    @ViewBuilder
    private func applyNavigationModifiers<V: View>(to view: V, selectedVault: Vault) -> some View {
        view
#if os(macOS)
            .navigationDestination(isPresented: $showScanner) {
                MacScannerView(type: .SignTransaction, sendTx: sendTx, selectedVault: selectedVault)
            }
#else
            .crossPlatformSheet(isPresented: $showScanner) {
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    GeneralQRImportMacView(type: .SignTransaction, selectedVault: selectedVault) {
                        guard let url = URL(string: $0) else { return }
                        deeplinkViewModel.extractParameters(url, vaults: vaults)
                        presetValuesForDeeplink()
                    }
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
                vaultRoute = .mainAction(.send(coin: deeplinkChain ?? vaultDetailViewModel.selectedGroup?.nativeCoin, hasPreselectedCoin: true))
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
                VaultManagementSheet(isPresented: $showVaultSelector, availableHeight: capturedGeometryHeight) {
                    showVaultSelector.toggle()
                    vaultRoute = .createVault
                } onSelectVault: { vault in
                    showVaultSelector.toggle()
                    if deeplinkViewModel.pendingSendDeeplink {
                        // Check if this is address-only (has address but no assetChain/assetTicker)
                        let isAddressOnly = deeplinkViewModel.address != nil && 
                                          deeplinkViewModel.assetChain == nil && 
                                          deeplinkViewModel.assetTicker == nil
                        
                        if isAddressOnly {
                            if let address = deeplinkViewModel.address {
                                processAddressOnlyDeeplink(address: address, vault: vault)
                            }
                        } else {
                            handleSendDeeplinkAfterVaultSelection(vault: vault)
                        }
                    } else {
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
            onRefresh: { shouldRefresh = true }
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
        fetchVaultDescriptor.relationshipKeyPathsForPrefetching = [
            \.coins,
             \.hiddenTokens,
             \.referralCode,
             \.referredCode,
             \.defiPositions,
             \.bondPositions,
             \.stakePositions,
             \.lpPositions
        ]
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
        
        // CRITICAL: Only process deeplink if vaults are loaded
        // This ensures we have vaults available for Send flow
        // For NewVault, we don't need vaults, so process immediately
        if deeplinkViewModel.type == .NewVault {
            presetValuesForDeeplink()
        } else if !vaults.isEmpty {
            presetValuesForDeeplink()
        } else if deeplinkViewModel.type != nil {
            // Retry after a short delay if vaults are not loaded yet
            // This can happen when app is opened via deeplink
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !vaults.isEmpty && deeplinkViewModel.type != nil {
                    presetValuesForDeeplink()
                } else if deeplinkViewModel.type != nil {
                    // Try processing anyway - maybe there are no vaults yet
                    presetValuesForDeeplink()
                }
            }
        }
    }
    
    func presetValuesForDeeplink() {
        if let _ = vultExtensionViewModel.documentData {
            shouldImportBackup = true
        }
        
        guard let type = deeplinkViewModel.type else {
            return
        }
        
        // Reset type before processing to avoid re-triggering onChange
        deeplinkViewModel.type = nil
        
        switch type {
        case .NewVault:
            moveToCreateVaultView()
        case .SignTransaction:
            moveToVaultsView()
        case .Send:
            handleSendDeeplink()
        case .Unknown:
            handleAddressOnlyDeeplink()
        }
    }
    
    private func handleSendDeeplink() {
        // Validate minimum parameters (assetChain, assetTicker, toAddress)
        // Even if some are missing, we'll still proceed with what we have
        guard deeplinkViewModel.assetChain != nil || 
              deeplinkViewModel.assetTicker != nil ||
              deeplinkViewModel.address != nil else {
            // If no parameters at all, don't proceed
            return
        }
        
        // CRITICAL: If no vaults, we can't proceed
        guard !vaults.isEmpty else {
            // Wait a bit more and retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !vaults.isEmpty {
                    handleSendDeeplink()
                }
            }
            return
        }
        
        // If only 1 vault, go directly to Send without showing selector
        if vaults.count == 1, let singleVault = vaults.first {
            // Close scanner if open
            if showScanner {
                showScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.handleSendDeeplinkAfterVaultSelection(vault: singleVault)
                }
            } else {
                handleSendDeeplinkAfterVaultSelection(vault: singleVault)
            }
            return
        }
        
        // Multiple vaults: show selector
        
        // CRITICAL: Close scanner first if it's open, then show vault selector
        // SwiftUI doesn't allow multiple sheets to be presented simultaneously
        if showScanner {
            showScanner = false
            
            // Wait for scanner to close, then show vault selector
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                deeplinkViewModel.pendingSendDeeplink = true
                showVaultSelector = true
            }
        } else {
            deeplinkViewModel.pendingSendDeeplink = true
            showVaultSelector = true
        }
    }
    
    func onVaultLoaded(vault: Vault) {
        // Enable chains for Defi tab if needed, only once per vault lifecycle
        Task { @MainActor in
            await VaultDefiChainsService().enableDefiChainsIfNeeded(for: vault)
        }
    }
    
    private func handleSendDeeplinkAfterVaultSelection(vault: Vault) {
        deeplinkViewModel.pendingSendDeeplink = false
        
        // Set the selected vault
        homeViewModel.setSelectedVault(vault)
        
        // Find the coin using the helper from DeeplinkViewModel
        let coin = deeplinkViewModel.findCoin(in: vault)
        
        // Reset SendTransaction appropriately
        // IMPORTANT: Save deeplink values BEFORE reset (reset clears all fields)
        let savedAddress = deeplinkViewModel.address
        let savedAmount = deeplinkViewModel.sendAmount
        let savedMemo = deeplinkViewModel.sendMemo
        
        let coinToUse: Coin?
        if let coin = coin {
            coinToUse = coin
            sendTx.reset(coin: coin)
        } else {
            // If coin not found, reset with a default coin from vault (or keep current state)
            // The Send screen will handle missing coin gracefully
            if let defaultCoin = vault.coins.first {
                coinToUse = defaultCoin
                sendTx.reset(coin: defaultCoin)
            } else {
                coinToUse = nil
            }
        }
        
        // Pre-fill fields AFTER reset (reset clears all fields, so we need to set them again)
        
        if let address = savedAddress {
            sendTx.toAddress = address
        }
        
        if let amount = savedAmount {
            sendTx.amount = amount
        }
        
        if let memo = savedMemo {
            sendTx.memo = memo
        }
        
        // Navigate to Send screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            vaultRoute = .mainAction(.send(coin: coinToUse, hasPreselectedCoin: coinToUse != nil))
        }
        
        // Don't clear deeplink state yet - SendDetailsScreen needs it in onLoad
        // It will clear it after reading the address
    }
    
    private func handleAddressOnlyDeeplink() {
        // Validate that we have an address
        guard let address = deeplinkViewModel.address, !address.isEmpty else {
            return
        }
        
        // If only 1 vault, go directly to Send without showing selector
        if vaults.count == 1, let singleVault = vaults.first {
            // Close scanner if open
            if showScanner {
                showScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.processAddressOnlyDeeplink(address: address, vault: singleVault)
                }
            } else {
                processAddressOnlyDeeplink(address: address, vault: singleVault)
            }
            return
        }
        
        // Multiple vaults: show selector for address-only too
        
        // Set flag to indicate this is address-only deeplink
        deeplinkViewModel.pendingSendDeeplink = true
        
        // CRITICAL: Close scanner first if it's open
        // SwiftUI doesn't allow multiple sheets to be presented simultaneously
        if showScanner {
            showScanner = false
            
            // Wait for scanner to close, then show vault selector
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showVaultSelector = true
            }
        } else {
            showVaultSelector = true
        }
    }
    
    private func processAddressOnlyDeeplink(address: String, vault: Vault) {
        // Set the selected vault
        homeViewModel.setSelectedVault(vault)
        
        // Detect chain from address format (similar to QR scanner logic)
        var coinToUse: Coin?
        
        // First, try to detect chain by validating address against vault coins
        
        // Check MayaChain first (special case)
        if address.lowercased().contains("maya") {
            coinToUse = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken })
        }
        
        // If not MayaChain, iterate through vault coins to find matching chain
        if coinToUse == nil {
            for coin in vault.coins where coin.isNativeToken {
                // Special handling for MayaChain and ThorChain Stagenet
                if coin.chain == .mayaChain {
                    if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya") {
                        coinToUse = coin
                        break
                    }
                } else if coin.chain == .thorChainStagenet {
                    if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "sthor") {
                        coinToUse = coin
                        break
                    }
                } else {
                    // Validate address against chain's coinType
                    let isValid = coin.chain.coinType.validate(address: address)
                    if isValid {
                        coinToUse = coin
                        break
                    }
                }
            }
        }
        
        // Fallback: use first native token if no chain detected
        if coinToUse == nil {
            coinToUse = vault.coins.first(where: { $0.isNativeToken }) ?? vault.coins.first
        }
        
        if let coin = coinToUse {
            sendTx.reset(coin: coin)
        }
        
        // Pre-fill address in both sendTx and deeplinkViewModel
        // SendDetailsScreen reads from deeplinkViewModel.address in onLoad
        sendTx.toAddress = address
        deeplinkViewModel.address = address
        
        // Don't clear deeplink state yet - SendDetailsScreen needs it in onLoad
        // It will clear it after reading the address
        
        // Navigate to Send screen directly (no vault selector)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.vaultRoute = .mainAction(.send(coin: coinToUse, hasPreselectedCoin: coinToUse != nil))
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
