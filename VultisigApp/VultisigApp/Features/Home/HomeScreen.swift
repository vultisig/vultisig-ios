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
            #if DEBUG
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📱 HomeScreen: onAppear - Tela apareceu")
            print("   selectedVault: \(homeViewModel.selectedVault?.name ?? "nil")")
            print("   showVaultSelector: \(showVaultSelector)")
            print("   showScanner: \(showScanner)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            #endif
        }
        .onLoad {
            #if DEBUG
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📱 HomeScreen: onLoad - Carregando dados iniciais")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            #endif
            setData()
            showVaultSelector = showingVaultSelector
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ProcessDeeplink"))) { _ in
            #if DEBUG
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔔 NOTIFICAÇÃO ProcessDeeplink recebida")
            print("   type atual: \(String(describing: deeplinkViewModel.type))")
            print("   showScanner atual: \(showScanner)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            #endif
            
            // If scanner is open and this is a Send deeplink, close scanner first
            if showScanner && deeplinkViewModel.type == .Send {
                #if DEBUG
                print("   ⚠️ Scanner está aberto e type é .Send, fechando scanner primeiro...")
                #endif
                showScanner = false
                
                // Wait for scanner to close, then process deeplink
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    #if DEBUG
                    print("   ✅ Scanner fechado, processando deeplink agora")
                    #endif
                    presetValuesForDeeplink()
                }
            } else {
                presetValuesForDeeplink()
            }
        }
        .onChange(of: deeplinkViewModel.type) { oldValue, newValue in
            #if DEBUG
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔥 ONCHANGE DISPARADO - deeplinkViewModel.type")
            print("   oldValue: \(String(describing: oldValue))")
            print("   newValue: \(String(describing: newValue))")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            #endif
            
            // Process deeplink when type changes (e.g., when app is already open and QR code is scanned)
            if newValue != nil {
                #if DEBUG
                print("   ✅ newValue não é nil, chamando presetValuesForDeeplink()")
                #endif
                presetValuesForDeeplink()
            } else {
                #if DEBUG
                print("   ⚠️ newValue é nil, não fazendo nada")
                #endif
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
                #if DEBUG
                print("📱 HomeScreen: Botão QR Scanner CLICADO - showScanner: \(showScanner), tab: \(selectedTab)")
                #endif
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
                #if DEBUG
                print("📱 HomeScreen.content: onAppear - Vault: \(selectedVault.name), height: \(geo.size.height)")
                #endif
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
                #if DEBUG
                print("📱 HomeScreen: selectedTab mudou: \(oldValue) -> \(newValue)")
                #endif
                
                updateHeader()
                if newValue == .camera {
                    #if DEBUG
                    print("   ⚠️ Tab mudou para .camera, resetando e chamando onCamera()")
                    #endif
                    selectedTab = oldValue
                    onCamera()
                }
            }
            .navigationDestination(item: $vaultRoute) { route in
                #if DEBUG
                let _ = print("📱 HomeScreen: navigationDestination vaultRoute: \(route)")
                #endif
                buildVaultRoute(route: route, vault: selectedVault)
            }
        
        return applyNavigationModifiers(to: withBasicModifiers, selectedVault: selectedVault)
    }
    
    @ViewBuilder
    private func applyNavigationModifiers<V: View>(to view: V, selectedVault: Vault) -> some View {
        view
#if os(macOS)
            .navigationDestination(isPresented: $showScanner) {
                #if DEBUG
                let _ = print("📱 HomeScreen: navigationDestination para showScanner: \(showScanner) - Criando MacScannerView")
                #endif
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
                    #if DEBUG
                    print("🔍 VaultManagementSheet: onCreate ação")
                    #endif
                    showVaultSelector.toggle()
                    vaultRoute = .createVault
                } onSelectVault: { vault in
                    #if DEBUG
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("🔥 VAULT SELECIONADO: \(vault.name)")
                    print("   pendingSendDeeplink: \(deeplinkViewModel.pendingSendDeeplink)")
                    print("   address: \(deeplinkViewModel.address ?? "nil")")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    #endif
                    
                    showVaultSelector.toggle()
                    if deeplinkViewModel.pendingSendDeeplink {
                        // Check if this is address-only (has address but no assetChain/assetTicker)
                        let isAddressOnly = deeplinkViewModel.address != nil && 
                                          deeplinkViewModel.assetChain == nil && 
                                          deeplinkViewModel.assetTicker == nil
                        
                        if isAddressOnly {
                            #if DEBUG
                            print("   ✅ Fluxo Address-only deeplink detectado")
                            #endif
                            if let address = deeplinkViewModel.address {
                                processAddressOnlyDeeplink(address: address, vault: vault)
                            }
                        } else {
                            #if DEBUG
                            print("   ✅ Fluxo Send deeplink detectado")
                            #endif
                            handleSendDeeplinkAfterVaultSelection(vault: vault)
                        }
                    } else {
                        #if DEBUG
                        print("   ℹ️ Fluxo normal de seleção de vault")
                        #endif
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
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 HomeScreen.onCamera chamado")
        print("   showScanner ANTES: \(showScanner)")
        #endif
        
        showScanner = true
        
        #if DEBUG
        print("   showScanner DEPOIS: \(showScanner)")
        print("   ✅ Scanner deve abrir agora")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
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
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📱 HomeScreen.setData INICIADO")
        print("   initialVault: \(initialVault?.name ?? "nil")")
        print("   showingVaultSelector: \(showingVaultSelector)")
        print("   vaults.count: \(vaults.count)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        fetchVaults()
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        homeViewModel.selectedVault = nil
        checkUpdate()
        
        if let vault = initialVault {
            #if DEBUG
            print("   ✅ initialVault presente: \(vault.name)")
            print("   Setando como selectedVault e retornando")
            #endif
            homeViewModel.setSelectedVault(vault)
            selectedVault = nil
            return
        } else {
            #if DEBUG
            print("   initialVault é nil, carregando vault selecionado...")
            #endif
            homeViewModel.loadSelectedVault(for: vaults)
        }
        
        #if DEBUG
        print("   Chamando presetValuesForDeeplink() de setData()")
        #endif
        presetValuesForDeeplink()
        
        #if DEBUG
        print("📱 HomeScreen.setData CONCLUÍDO")
        print("")
        #endif
    }
    
    func presetValuesForDeeplink() {
        if let _ = vultExtensionViewModel.documentData {
            shouldImportBackup = true
        }
        
        #if DEBUG
        print("🔍 presetValuesForDeeplink chamado")
        print("   deeplinkViewModel.type: \(String(describing: deeplinkViewModel.type))")
        #endif
        
        guard let type = deeplinkViewModel.type else {
            #if DEBUG
            print("   ⚠️ type é nil, abortando")
            #endif
            return
        }
        
        #if DEBUG
        print("   ✅ type encontrado: \(type)")
        print("   → Setando type para nil ANTES de processar")
        #endif
        
        // Reset type before processing to avoid re-triggering onChange
        deeplinkViewModel.type = nil
        
        switch type {
        case .NewVault:
            #if DEBUG
            print("   → Chamando moveToCreateVaultView()")
            #endif
            moveToCreateVaultView()
        case .SignTransaction:
            #if DEBUG
            print("   → Chamando moveToVaultsView()")
            #endif
            moveToVaultsView()
        case .Send:
            #if DEBUG
            print("   → Chamando handleSendDeeplink()")
            #endif
            handleSendDeeplink()
        case .Unknown:
            #if DEBUG
            print("   → Type é Unknown, processando como address-only deeplink")
            #endif
            handleAddressOnlyDeeplink()
        }
    }
    
    private func handleSendDeeplink() {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔥 handleSendDeeplink INICIADO")
        print("   assetChain: \(deeplinkViewModel.assetChain ?? "nil")")
        print("   assetTicker: \(deeplinkViewModel.assetTicker ?? "nil")")
        print("   address: \(deeplinkViewModel.address ?? "nil")")
        print("   sendAmount: \(deeplinkViewModel.sendAmount ?? "nil")")
        print("   sendMemo: \(deeplinkViewModel.sendMemo ?? "nil")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        // Validate minimum parameters (assetChain, assetTicker, toAddress)
        // Even if some are missing, we'll still proceed with what we have
        guard deeplinkViewModel.assetChain != nil || 
              deeplinkViewModel.assetTicker != nil ||
              deeplinkViewModel.address != nil else {
            // If no parameters at all, don't proceed
            #if DEBUG
            print("⚠️ handleSendDeeplink: Nenhum parâmetro encontrado, abortando")
            #endif
            return
        }
        
        #if DEBUG
        print("✅ handleSendDeeplink: Validação passou")
        print("   showScanner atual: \(showScanner)")
        print("   vaults.count: \(vaults.count)")
        print("   showVaultSelector ANTES: \(showVaultSelector)")
        #endif
        
        // If only 1 vault, go directly to Send without showing selector
        if vaults.count == 1, let singleVault = vaults.first {
            #if DEBUG
            print("   ✅ Apenas 1 vault encontrado, indo direto para Send")
            print("   Vault: \(singleVault.name)")
            #endif
            
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
        #if DEBUG
        print("   ℹ️ Múltiplos vaults (\(vaults.count)), mostrando seletor")
        #endif
        
        // CRITICAL: Close scanner first if it's open, then show vault selector
        // SwiftUI doesn't allow multiple sheets to be presented simultaneously
        if showScanner {
            #if DEBUG
            print("   ⚠️ Scanner está aberto, fechando primeiro...")
            #endif
            showScanner = false
            
            // Wait for scanner to close, then show vault selector
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                #if DEBUG
                print("   ✅ Scanner fechado, agora mostrando vault selector")
                #endif
                deeplinkViewModel.pendingSendDeeplink = true
                showVaultSelector = true
            }
        } else {
            #if DEBUG
            print("   ✅ Scanner não está aberto, mostrando vault selector imediatamente")
            #endif
            deeplinkViewModel.pendingSendDeeplink = true
            showVaultSelector = true
        }
        
        #if DEBUG
        print("   showVaultSelector DEPOIS: \(showVaultSelector)")
        print("   ✅ Vault selector deve aparecer agora")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
    }
    
    func onVaultLoaded(vault: Vault) {
        // Enable chains for Defi tab if needed, only once per vault lifecycle
        Task { @MainActor in
            await VaultDefiChainsService().enableDefiChainsIfNeeded(for: vault)
        }
    }
    
    private func handleSendDeeplinkAfterVaultSelection(vault: Vault) {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔥 handleSendDeeplinkAfterVaultSelection INICIADO")
        print("   Vault: \(vault.name)")
        print("   Vault tem \(vault.coins.count) coins")
        print("   assetChain no deeplink: \(deeplinkViewModel.assetChain ?? "nil")")
        print("   assetTicker no deeplink: \(deeplinkViewModel.assetTicker ?? "nil")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        deeplinkViewModel.pendingSendDeeplink = false
        
        // Set the selected vault
        homeViewModel.setSelectedVault(vault)
        
        // Find the coin using the helper from DeeplinkViewModel
        #if DEBUG
        print("   🔍 Buscando coin no vault...")
        #endif
        let coin = deeplinkViewModel.findCoin(in: vault)
        
        #if DEBUG
        if let coin = coin {
            print("   ✅ Coin encontrada: \(coin.ticker) na chain \(coin.chain.rawValue)")
        } else {
            print("   ⚠️ Coin NÃO encontrada!")
            print("   Vou usar a primeira coin do vault como fallback")
        }
        #endif
        
        // Reset SendTransaction appropriately
        // IMPORTANT: Save deeplink values BEFORE reset (reset clears all fields)
        let savedAddress = deeplinkViewModel.address
        let savedAmount = deeplinkViewModel.sendAmount
        let savedMemo = deeplinkViewModel.sendMemo
        
        let coinToUse: Coin?
        if let coin = coin {
            coinToUse = coin
            sendTx.reset(coin: coin)
            #if DEBUG
            print("   ✅ sendTx.reset(coin: \(coin.ticker)) executado")
            #endif
        } else {
            // If coin not found, reset with a default coin from vault (or keep current state)
            // The Send screen will handle missing coin gracefully
            if let defaultCoin = vault.coins.first {
                coinToUse = defaultCoin
                sendTx.reset(coin: defaultCoin)
                #if DEBUG
                print("   ✅ sendTx.reset(coin: \(defaultCoin.ticker)) executado (fallback)")
                #endif
            } else {
                coinToUse = nil
                #if DEBUG
                print("   ⚠️ Vault não tem coins! sendTx não foi resetado")
                #endif
            }
        }
        
        // Pre-fill fields AFTER reset (reset clears all fields, so we need to set them again)
        #if DEBUG
        print("   📝 Preenchendo campos do sendTx APÓS reset...")
        #endif
        
        if let address = savedAddress {
            sendTx.toAddress = address
            #if DEBUG
            print("   ✅ toAddress definido: \(address)")
            #endif
        } else {
            #if DEBUG
            print("   ⚠️ address é nil, não preenchendo toAddress")
            #endif
        }
        
        if let amount = savedAmount {
            sendTx.amount = amount
            #if DEBUG
            print("   ✅ amount definido: \(amount)")
            #endif
        } else {
            #if DEBUG
            print("   ⚠️ sendAmount é nil, não preenchendo amount")
            #endif
        }
        
        if let memo = savedMemo {
            sendTx.memo = memo
            #if DEBUG
            print("   ✅ memo definido: \(memo)")
            #endif
        } else {
            #if DEBUG
            print("   ⚠️ sendMemo é nil, não preenchendo memo")
            #endif
        }
        
        #if DEBUG
        print("   📊 Estado final do sendTx:")
        print("      coin: \(sendTx.coin.ticker)")
        print("      toAddress: \(sendTx.toAddress)")
        print("      amount: \(sendTx.amount)")
        print("      memo: \(sendTx.memo)")
        print("   ✅ Todos os campos preenchidos")
        print("   🚀 Preparando navegação para Send screen...")
        #endif
        
        // Navigate to Send screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            #if DEBUG
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🚀 EXECUTANDO NAVEGAÇÃO PARA SEND")
            print("   coin: \(coinToUse?.ticker ?? "nil")")
            print("   hasPreselectedCoin: \(coinToUse != nil)")
            print("   vaultRoute ANTES: \(String(describing: vaultRoute))")
            #endif
            
            vaultRoute = .mainAction(.send(coin: coinToUse, hasPreselectedCoin: coinToUse != nil))
            
            #if DEBUG
            print("   vaultRoute DEPOIS: \(String(describing: vaultRoute))")
            print("   ✅ Navegação executada!")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            #endif
        }
        
        // Don't clear deeplink state yet - SendDetailsScreen needs it in onLoad
        // It will clear it after reading the address
        #if DEBUG
        print("   ℹ️ Mantendo deeplinkViewModel.address para SendDetailsScreen ler")
        #endif
        
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")
        #endif
    }
    
    private func handleAddressOnlyDeeplink() {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔥 handleAddressOnlyDeeplink INICIADO")
        print("   address: \(deeplinkViewModel.address ?? "nil")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        // Validate that we have an address
        guard let address = deeplinkViewModel.address, !address.isEmpty else {
            #if DEBUG
            print("   ⚠️ Nenhum endereço encontrado, abortando")
            #endif
            return
        }
        
        #if DEBUG
        print("   ✅ Endereço encontrado: \(address)")
        print("   showScanner atual: \(showScanner)")
        print("   vaults.count: \(vaults.count)")
        #endif
        
        // If only 1 vault, go directly to Send without showing selector
        if vaults.count == 1, let singleVault = vaults.first {
            #if DEBUG
            print("   ✅ Apenas 1 vault encontrado, indo direto para Send (address-only)")
            print("   Vault: \(singleVault.name)")
            #endif
            
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
        #if DEBUG
        print("   ℹ️ Múltiplos vaults (\(vaults.count)), mostrando seletor para address-only")
        #endif
        
        // Set flag to indicate this is address-only deeplink
        deeplinkViewModel.pendingSendDeeplink = true
        
        // CRITICAL: Close scanner first if it's open
        // SwiftUI doesn't allow multiple sheets to be presented simultaneously
        if showScanner {
            #if DEBUG
            print("   ⚠️ Scanner está aberto, fechando primeiro...")
            #endif
            showScanner = false
            
            // Wait for scanner to close, then show vault selector
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                #if DEBUG
                print("   ✅ Scanner fechado, mostrando vault selector para address-only")
                #endif
                showVaultSelector = true
            }
        } else {
            #if DEBUG
            print("   ✅ Scanner não está aberto, mostrando vault selector imediatamente")
            #endif
            showVaultSelector = true
        }
    }
    
    private func processAddressOnlyDeeplink(address: String, vault: Vault) {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📝 processAddressOnlyDeeplink")
        print("   address: \(address)")
        print("   vault: \(vault.name)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        // Set the selected vault
        homeViewModel.setSelectedVault(vault)
        
        #if DEBUG
        print("   📋 Vault tem \(vault.coins.count) coins")
        #endif
        
        // Detect chain from address format (similar to QR scanner logic)
        var coinToUse: Coin?
        
        // First, try to detect chain by validating address against vault coins
        #if DEBUG
        print("   🔍 Detectando chain pelo formato do endereço...")
        #endif
        
        // Check MayaChain first (special case)
        if address.lowercased().contains("maya") {
            coinToUse = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken })
            if coinToUse != nil {
                #if DEBUG
                print("   ✅ Detectado MayaChain pelo prefixo 'maya'")
                #endif
            }
        }
        
        // If not MayaChain, iterate through vault coins to find matching chain
        if coinToUse == nil {
            for coin in vault.coins where coin.isNativeToken {
                // Special handling for MayaChain and ThorChain Stagenet
                if coin.chain == .mayaChain {
                    if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya") {
                        coinToUse = coin
                        #if DEBUG
                        print("   ✅ Detectado MayaChain pela validação Bech32")
                        #endif
                        break
                    }
                } else if coin.chain == .thorChainStagenet {
                    if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "sthor") {
                        coinToUse = coin
                        #if DEBUG
                        print("   ✅ Detectado ThorChain Stagenet pela validação Bech32")
                        #endif
                        break
                    }
                } else {
                    // Validate address against chain's coinType
                    let isValid = coin.chain.coinType.validate(address: address)
                    if isValid {
                        coinToUse = coin
                        #if DEBUG
                        print("   ✅ Detectado \(coin.chain.rawValue) pela validação do endereço")
                        #endif
                        break
                    }
                }
            }
        }
        
        // Fallback: use first native token if no chain detected
        if coinToUse == nil {
            coinToUse = vault.coins.first(where: { $0.isNativeToken }) ?? vault.coins.first
            #if DEBUG
            if let fallback = coinToUse {
                print("   ⚠️ Chain não detectada, usando fallback: \(fallback.chain.rawValue) - \(fallback.ticker)")
            } else {
                print("   ❌ Nenhuma coin disponível no vault!")
            }
            #endif
        }
        
        if let coin = coinToUse {
            sendTx.reset(coin: coin)
            #if DEBUG
            print("   ✅ sendTx.reset(coin: \(coin.ticker)) executado")
            #endif
        } else {
            #if DEBUG
            print("   ⚠️ Vault não tem coins! sendTx não foi resetado")
            #endif
        }
        
        // Pre-fill address in both sendTx and deeplinkViewModel
        // SendDetailsScreen reads from deeplinkViewModel.address in onLoad
        sendTx.toAddress = address
        deeplinkViewModel.address = address
        #if DEBUG
        print("   ✅ toAddress definido em sendTx e deeplinkViewModel: \(address)")
        #endif
        
        // Don't clear deeplink state yet - SendDetailsScreen needs it in onLoad
        // It will clear it after reading the address
        
        // Navigate to Send screen directly (no vault selector)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            #if DEBUG
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🚀 EXECUTANDO NAVEGAÇÃO PARA SEND (address-only)")
            print("   coin: \(coinToUse?.ticker ?? "nil")")
            print("   hasPreselectedCoin: \(coinToUse != nil)")
            print("   vaultRoute ANTES: \(String(describing: self.vaultRoute))")
            #endif
            
            self.vaultRoute = .mainAction(.send(coin: coinToUse, hasPreselectedCoin: coinToUse != nil))
            
            #if DEBUG
            print("   vaultRoute DEPOIS: \(String(describing: self.vaultRoute))")
            print("   ✅ Navegação executada!")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("")
            #endif
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
