//
//  HomeScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftData
import SwiftUI
import WalletCore

struct HomeScreen: View {
    @Environment(\.router) var router
    let showingVaultSelector: Bool

    @State var showVaultSelector: Bool = false
    @State var addressToCopy: Coin?
    @State var showUpgradeVaultSheet: Bool = false

    @State var vaults: [Vault] = []
    @State private var selectedTab: HomeTab = .wallet
    @State var vaultRoute: VaultMainRoute?

    @State var showScanner: Bool = false
    @State var showBackupNow = false
    @StateObject var sendTx = SendTransaction()
    @State var selectedChain: Chain? = nil

    @State var walletShowPortfolioHeader: Bool = false
    @State var defiShowPortfolioHeader: Bool = false
    @State var showPortfolioHeader: Bool = false
    @State var shouldRefresh: Bool = false
    @State var showChainMissingAlert: Bool = false
    @State var missingChainName: String = ""
    @State private var deeplinkError: Error?

    @State private var capturedGeometryHeight: CGFloat = 600

    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var phoneCheckUpdateViewModel: PhoneCheckUpdateViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext
    private let tabs: [HomeTab] = [.wallet, .defi]

    init(showingVaultSelector: Bool = false) {
        self.showingVaultSelector = showingVaultSelector
    }

    var body: some View {
        ZStack {
            if let selectedVault = appViewModel.selectedVault {
                content(selectedVault: selectedVault)
            } else {
                initialView
            }
        }
        .onLoad {
            showVaultSelector = showingVaultSelector
            setData()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("ProcessDeeplink"))
        ) { _ in

            if showScanner {
                showScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    presetValuesForDeeplink()
                }
            } else {
                presetValuesForDeeplink()
            }
        }
        .onChange(of: deeplinkViewModel.type) { _, newValue in
            if newValue != nil {
                presetValuesForDeeplink()
            }
        }
        .alert(
            NSLocalizedString("chainNotAdded", comment: ""),
            isPresented: $showChainMissingAlert
        ) {
            Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: NSLocalizedString("chainNotAddedMessage", comment: ""), missingChainName
                ))
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
                            shouldRefresh: $shouldRefresh,
                            onCamera: onCamera
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
    private func applyModifiers<V: View>(to view: V, selectedVault: Vault, geo: GeometryProxy)
    -> some View {
        let withBasicModifiers =
        view
            .onAppear {
                capturedGeometryHeight = geo.size.height
            }
            .onChange(of: geo.size.height) { _, newHeight in
                if !showVaultSelector {
                    capturedGeometryHeight = newHeight
                }
            }
            .sensoryFeedback(
                homeViewModel.showAlert ? .stop : .impact, trigger: homeViewModel.showAlert
            )
            .customNavigationBarHidden()
            .withAddressCopy(coin: $addressToCopy)
            .withUpgradeVault(vault: selectedVault, shouldShow: $showUpgradeVaultSheet)
            .withBiweeklyPasswordVerification(vault: selectedVault)
            .withMonthlyBackupWarning(vault: selectedVault)
            .onLoad {
                onVaultLoaded(vault: selectedVault)
            }
            .onChange(of: walletShowPortfolioHeader) { _, _ in updateHeader() }
            .onChange(of: defiShowPortfolioHeader) { _, _ in updateHeader() }
            .onChange(of: selectedTab) { _, newValue in
                updateHeader()
                if newValue == .camera {
                    onCamera()
                }
            }
            .onChange(of: appViewModel.showCamera) { _, newValue in
                guard newValue else { return }
                onCamera()
                appViewModel.showCamera = false
            }
            .onChange(of: vaultRoute) { _, route in
                guard let route else { return }

                switch route {
                case .settings:
                    router.navigate(to: SettingsRoute.main(vault: selectedVault))
                case .createVault:
                    router.navigate(to: VaultRoute.createVault(showBackButton: true))
                case .mainAction(let action):
                    router.navigate(to: HomeRoute.vaultAction(action: action, sendTx: sendTx, vault: selectedVault))
                }

                vaultRoute = nil
            }

        applyNavigationModifiers(to: withBasicModifiers, selectedVault: selectedVault)
    }

    @ViewBuilder
    private func applyNavigationModifiers<V: View>(to view: V, selectedVault: Vault) -> some View {
        view
#if os(macOS)
            .onChange(of: showScanner) { _, shouldNavigate in
                guard shouldNavigate else { return }
                router.navigate(to: KeygenRoute.macScanner(
                    type: .SignTransaction,
                    sendTx: sendTx,
                    selectedVault: selectedVault
                ))
                showScanner = false
            }
#else
            .crossPlatformSheet(isPresented: $showScanner) {
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    GeneralQRImportMacView(type: .SignTransaction, selectedVault: selectedVault) {
                        guard let url = URL(string: $0) else { return }
                        do {
                            try deeplinkViewModel.extractParameters(url, vaults: vaults, isInternal: true)
                            presetValuesForDeeplink()
                        } catch {
                            deeplinkError = error
                        }
                    }
                } else {
                    GeneralCodeScannerView(
                        showSheet: $showScanner,
                        selectedChain: $selectedChain,
                        sendTX: sendTx,
                        onJoinKeygen: {
                            navigateToJoinKeygen(selectedVault: selectedVault)
                        },
                        onKeysignTransaction: {
                            navigateToJoinKeysign()
                        },
                        onSendCrypto: {
                            navigateToSendCrypto(selectedVault: selectedVault)
                        }
                    )
                }
            }
#endif
            .onChange(of: showBackupNow) { _, shouldNavigate in
                guard shouldNavigate, let vault = appViewModel.selectedVault else { return }
                router.navigate(to: KeygenRoute.backupNow(
                    tssType: .Keygen,
                    backupType: .single(vault: vault),
                    isNewVault: false
                ))
                showBackupNow = false
            }
            .onChange(of: homeViewModel.shouldShowScanner) { _, newValue in
                if newValue {
                    showScanner = true
                    homeViewModel.shouldShowScanner = false
                }
            }
            .crossPlatformSheet(isPresented: $showVaultSelector) {
                VaultManagementSheet(
                    isPresented: $showVaultSelector, availableHeight: capturedGeometryHeight
                ) {
                    showVaultSelector.toggle()
                    vaultRoute = .createVault
                } onSelectVault: { vault in
                    showVaultSelector.toggle()
                    if deeplinkViewModel.pendingSendDeeplink {
                        let isAddressOnly =
                        deeplinkViewModel.address != nil && deeplinkViewModel.assetChain == nil
                        && deeplinkViewModel.assetTicker == nil

                        if isAddressOnly, let address = deeplinkViewModel.address {
                            processAddressOnlyDeeplink(address: address, vault: vault)
                        } else {
                            handleSendDeeplinkAfterVaultSelection(vault: vault)
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appViewModel.set(selectedVault: vault, restartNavigation: false)
                        }
                    }
                }
            }
            .withError(error: $deeplinkError, errorType: .warning) {
                // Retry action - reopen scanner
                showScanner = true
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

extension HomeScreen {
    fileprivate func updateHeader() {
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

    fileprivate func moveToVaultsView() {
        guard let vault = deeplinkViewModel.selectedVault else {
            return
        }

        appViewModel.set(selectedVault: vault, restartNavigation: false)
        showVaultSelector = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            navigateToJoinKeysign()
        }
    }

    fileprivate func checkUpdate() {
        phoneCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
    }

    fileprivate func moveToCreateVaultView() {
        guard let selectedVault = appViewModel.selectedVault else { return }
        showVaultSelector = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            navigateToJoinKeygen(selectedVault: selectedVault)
        }
    }

    fileprivate func onCamera() {
        showScanner = true
    }

    fileprivate func fetchVaults() {
        var fetchVaultDescriptor = FetchDescriptor<Vault>()
        fetchVaultDescriptor.relationshipKeyPathsForPrefetching = [
            \.coins,
             \.hiddenTokens,
             \.referralCode,
             \.referredCode,
             \.defiPositions,
             \.bondPositions,
             \.stakePositions,
             \.lpPositions,
             \.closedBanners
        ]
        do {
            vaults = try modelContext.fetch(fetchVaultDescriptor)
        } catch {
            print(error)
        }
    }

    fileprivate func setData() {
        appViewModel.authenticateUserIfNeeded()
        fetchVaults()
        checkUpdate()

        if deeplinkViewModel.type == .NewVault {
            presetValuesForDeeplink()
        } else if !vaults.isEmpty {
            presetValuesForDeeplink()
        } else if deeplinkViewModel.type != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !vaults.isEmpty && deeplinkViewModel.type != nil {
                    presetValuesForDeeplink()
                } else if deeplinkViewModel.type != nil {
                    presetValuesForDeeplink()
                }
            }
        }
    }

    fileprivate func presetValuesForDeeplink() {
        if vultExtensionViewModel.documentData != nil {
            navigateToImportBackup()
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
        case .Send:
            handleSendDeeplink()
        case .Unknown:
            handleAddressOnlyDeeplink()
        }
    }

    private func handleSendDeeplink() {
        guard
            deeplinkViewModel.assetChain != nil || deeplinkViewModel.assetTicker != nil
                || deeplinkViewModel.address != nil
        else {
            return
        }

        guard !vaults.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !vaults.isEmpty {
                    handleSendDeeplink()
                }
            }
            return
        }

        if deeplinkViewModel.isInternalDeeplink, let selectedVault = appViewModel.selectedVault {
            closeScannerIfNeeded {
                self.handleSendDeeplinkAfterVaultSelection(vault: selectedVault)
            }
            return
        }

        if vaults.count == 1, let singleVault = vaults.first {
            closeScannerIfNeeded {
                self.handleSendDeeplinkAfterVaultSelection(vault: singleVault)
            }
            return
        }

        closeScannerIfNeeded {
            self.deeplinkViewModel.pendingSendDeeplink = true
            self.showVaultSelector = true
        }
    }

    fileprivate func onVaultLoaded(vault: Vault) {
        Task { @MainActor in
            await VaultDefiChainsService().enableDefiChainsIfNeeded(for: vault)
        }
    }

    private func handleSendDeeplinkAfterVaultSelection(vault: Vault) {
        deeplinkViewModel.pendingSendDeeplink = false
        appViewModel.set(selectedVault: vault, restartNavigation: false)

        let coin = deeplinkViewModel.findCoin(in: vault)

        // Check if user specified a chain/token but it wasn't found in vault
        if coin == nil && deeplinkViewModel.assetChain != nil {
            // Chain/token missing in vault - alert user
            missingChainName = deeplinkViewModel.assetChain?.capitalized ?? "Unknown"
            showChainMissingAlert = true

            // Reset deeplink data to prevent stuck state
            deeplinkViewModel.resetData()
            return
        }

        let savedAddress = deeplinkViewModel.address
        let savedAmount = deeplinkViewModel.sendAmount
        let savedMemo = deeplinkViewModel.sendMemo

        let coinToUse: Coin?
        if let coin = coin {
            coinToUse = coin
            sendTx.reset(coin: coin)
        } else if let defaultCoin = vault.coins.first {
            coinToUse = defaultCoin
            sendTx.reset(coin: defaultCoin)
        } else {
            coinToUse = nil
        }

        if let address = savedAddress {
            sendTx.toAddress = address
        }
        if let amount = savedAmount {
            sendTx.amount = amount
        }
        if let memo = savedMemo {
            sendTx.memo = memo
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            vaultRoute = .mainAction(.send(coin: coinToUse, hasPreselectedCoin: coinToUse != nil))
        }
    }

    private func handleAddressOnlyDeeplink() {
        guard let address = deeplinkViewModel.address, !address.isEmpty else {
            return
        }

        if deeplinkViewModel.isInternalDeeplink, let selectedVault = appViewModel.selectedVault {
            closeScannerIfNeeded {
                self.processAddressOnlyDeeplink(address: address, vault: selectedVault)
            }
            return
        }

        if vaults.count == 1, let singleVault = vaults.first {
            closeScannerIfNeeded {
                self.processAddressOnlyDeeplink(address: address, vault: singleVault)
            }
            return
        }

        deeplinkViewModel.pendingSendDeeplink = true
        closeScannerIfNeeded {
            self.showVaultSelector = true
        }
    }

    private func processAddressOnlyDeeplink(address: String, vault: Vault) {
        appViewModel.set(selectedVault: vault, restartNavigation: false)

        var coinToUse: Coin?

        if address.lowercased().contains("maya") {
            coinToUse = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken })
        }

        if coinToUse == nil {
            for coin in vault.coins where coin.isNativeToken {
                if coin.chain == .mayaChain {
                    if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya") {
                        coinToUse = coin
                        break
                    }
                } else {
                    let isValid = coin.chain.coinType.validate(address: address)
                    if isValid {
                        coinToUse = coin
                        break
                    }
                }
            }
        }

        if coinToUse == nil {
            missingChainName = "Unknown"
            showChainMissingAlert = true
            deeplinkViewModel.resetData()
            return
        }

        if let coin = coinToUse {
            sendTx.reset(coin: coin)
        }

        sendTx.toAddress = address
        deeplinkViewModel.address = address

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.vaultRoute = .mainAction(
                .send(coin: coinToUse, hasPreselectedCoin: coinToUse != nil))
        }
    }

    private func closeScannerIfNeeded(completion: @escaping () -> Void) {
        if showScanner {
            showScanner = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                completion()
            }
        } else {
            completion()
        }
    }

    // MARK: - Navigation Methods

    fileprivate func navigateToJoinKeygen(selectedVault: Vault) {
        router.navigate(to: OnboardingRoute.joinKeygen(
            vault: Vault(name: "Main Vault"),
            selectedVault: selectedVault
        ))
    }

    fileprivate func navigateToJoinKeysign() {
        guard let vault = appViewModel.selectedVault else { return }
        router.navigate(to: KeygenRoute.joinKeysign(vault: vault))
    }

    fileprivate func navigateToSendCrypto(selectedVault: Vault) {
        let deeplinkChain = selectedVault.coins.first(where: {
            $0.isNativeToken && selectedChain == $0.chain
        })
        vaultRoute = .mainAction(
            .send(
                coin: deeplinkChain ?? vaultDetailViewModel.selectedGroup?.nativeCoin,
                hasPreselectedCoin: true))
    }

    fileprivate func navigateToImportBackup() {
        router.navigate(to: OnboardingRoute.importVaultShare)
    }
}

#Preview {
    HomeScreen(showingVaultSelector: false)
        .environmentObject(VaultDetailViewModel())
        .environmentObject(AppViewModel())
}
