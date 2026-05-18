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
    @State var selectedChain: Chain? = nil

    @State var walletShowPortfolioHeader: Bool = false
    @State var defiShowPortfolioHeader: Bool = false
    @State var showPortfolioHeader: Bool = false
    @State var shouldRefresh: Bool = false
    @State private var deeplinkError: Error?

    @State private var capturedGeometryHeight: CGFloat = 600
    /// Cancellable delayed-UI-mutation tasks keyed by trigger. The dictionary
    /// preserves per-call-site replace semantics (firing the same trigger
    /// twice cancels the prior in-flight task before scheduling the new one)
    /// while `cancelDelayedTasks()` on `.onDisappear` clears every pending
    /// task in one shot. See [[fix-macos-cancellable-ui-delays]].
    @State private var delayedTasks: [DelayedTaskID: Task<Void, Never>] = [:]

    /// Identifiers for the deferred UI mutations on this screen. One case
    /// per trigger; names mirror the prior `<name>Task` `@State` vars.
    private enum DelayedTaskID: Hashable {
        case processDeeplink
        case selectVault
        case joinKeysign
        case joinKeygen
        case initialDeeplink
        case retrySendDeeplink
        case sendRoute
        case addressOnlyRoute
        case scannerClose
    }

    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var phoneCheckUpdateViewModel: PhoneCheckUpdateViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @EnvironmentObject var appViewModel: AppViewModel
    @ObservedObject private var transactionPoller = TransactionStatusPoller.shared
    @Environment(\.modelContext) private var modelContext

    var tabs: [HomeTab] {
        var baseTabs: [HomeTab] = [.wallet]
        if !(appViewModel.selectedVault?.availableDefiChains.isEmpty ?? true) {
            baseTabs.append(.defi)
        }
        return baseTabs
    }

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
                scheduleDelayedTask(.processDeeplink, after: .milliseconds(300)) {
                    presetValuesForDeeplink()
                }
            } else {
                presetValuesForDeeplink()
            }
        }
        .onChange(of: appViewModel.restartNavigation) { _, newValue in
            guard newValue else { return }
            if let vault = appViewModel.selectedVault {
                transactionPoller.pollPendingTransactions(pubKeyECDSA: vault.pubKeyECDSA)
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    shouldRefresh = true
                }
            }
        }
        .onChange(of: transactionPoller.completedTransactionCount) { _, _ in
            shouldRefresh = true
        }
        .onChange(of: deeplinkViewModel.type) { _, newValue in
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

            #if os(macOS)
            Link(destination: StaticURL.GitHubReleasesURL) {
                Text(NSLocalizedString("downloadViaGitHub", comment: ""))
            }
            #endif

            Button(NSLocalizedString("dismiss", comment: ""), role: .cancel) {}
        } message: {
            Text(phoneCheckUpdateViewModel.latestVersionString)
        }
        .onDisappear {
            cancelDelayedTasks()
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
            .withSetupPushNotifications(vault: selectedVault)
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
                    router.navigate(to: HomeRoute.vaultAction(action: action, vault: selectedVault))
                case .transactionHistory:
                    router.navigate(to: TransactionHistoryRoute.list(
                        pubKeyECDSA: selectedVault.pubKeyECDSA,
                        vaultName: selectedVault.name,
                        chainFilter: nil
                    ))
                case .quantumSecurityIntro(let vault):
                    router.navigate(to: KeygenRoute.quantumSecurityIntro(vault: vault))
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
                        scheduleDelayedTask(.selectVault, after: .milliseconds(300)) {
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
            historyAction: { vaultRoute = .transactionHistory },
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
        scheduleDelayedTask(.joinKeysign, after: .milliseconds(100)) {
            navigateToJoinKeysign()
        }
    }

    fileprivate func checkUpdate() {
        phoneCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
    }

    fileprivate func moveToCreateVaultView() {
        guard let selectedVault = appViewModel.selectedVault else { return }
        showVaultSelector = false
        scheduleDelayedTask(.joinKeygen, after: .milliseconds(100)) {
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
            scheduleDelayedTask(.initialDeeplink, after: .milliseconds(800)) {
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
            // Clear fields that CreateVaultView also checks, preventing double navigation.
            // Keep receivedUrl intact — JoinKeygenView reads it for QR data.
            deeplinkViewModel.tssType = nil
            deeplinkViewModel.jsonData = nil
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
            scheduleDelayedTask(.retrySendDeeplink, after: .seconds(1)) {
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
        transactionPoller.pollPendingTransactions(pubKeyECDSA: vault.pubKeyECDSA)
    }

    private func handleSendDeeplinkAfterVaultSelection(vault: Vault) {
        deeplinkViewModel.pendingSendDeeplink = false
        appViewModel.set(selectedVault: vault, restartNavigation: false)

        let coin = deeplinkViewModel.findCoin(in: vault)

        // Check if user specified a chain/token but it wasn't found in vault
        if coin == nil && deeplinkViewModel.assetChain != nil {
            let chainName = deeplinkViewModel.assetChain?.capitalized ?? "Unknown"
            deeplinkError = DeeplinkError.chainNotAdded(chainName: chainName)
            deeplinkViewModel.resetData()
            return
        }

        let savedAddress = deeplinkViewModel.address
        let savedAmount = deeplinkViewModel.sendAmount
        let savedMemo = deeplinkViewModel.sendMemo

        let coinToUse: Coin? = coin ?? vault.coins.first

        scheduleDelayedTask(.sendRoute, after: .milliseconds(300)) {
            vaultRoute = .mainAction(.send(
                coin: coinToUse,
                hasPreselectedCoin: coinToUse != nil,
                prefilledToAddress: savedAddress,
                prefilledAmount: savedAmount,
                prefilledMemo: savedMemo
            ))
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
        var chainToUse: Chain?
        for chain in Chain.allCases {
            if chain == .mayaChain {
                if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya") {
                    chainToUse = chain
                    break
                }
            } else {
                let isValid = chain.coinType.validate(address: address)
                if isValid {
                    chainToUse = chain
                    break
                }
            }
        }

        if let chainToUse {
            coinToUse = vault.coins.first { $0.chain == chainToUse && $0.isNativeToken }
        } else if address.lowercased().contains("maya") {
            chainToUse = .mayaChain
            coinToUse = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken })
        }

        if chainToUse == nil {
            deeplinkError = DeeplinkError.unrelatedQRCode
            deeplinkViewModel.resetData()
            return
        }

        if coinToUse == nil {
            let chainName = chainToUse?.name ?? "Unknown"
            deeplinkError = DeeplinkError.chainNotAdded(chainName: chainName)
            deeplinkViewModel.resetData()
            return
        }

        deeplinkViewModel.address = address

        scheduleDelayedTask(.addressOnlyRoute, after: .milliseconds(300)) {
            self.vaultRoute = .mainAction(
                .send(
                    coin: coinToUse,
                    hasPreselectedCoin: coinToUse != nil,
                    prefilledToAddress: address
                ))
        }
    }

    private func closeScannerIfNeeded(completion: @escaping () -> Void) {
        if showScanner {
            showScanner = false
            scheduleDelayedTask(.scannerClose, after: .milliseconds(300)) {
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
        let fallbackCoin = vaultDetailViewModel.selectedChain.flatMap { selectedVault.nativeCoin(for: $0) }
        vaultRoute = .mainAction(
            .send(
                coin: deeplinkChain ?? fallbackCoin,
                hasPreselectedCoin: true))
    }

    fileprivate func navigateToImportBackup() {
        router.navigate(to: OnboardingRoute.importVaultShare)
    }
}

private extension HomeScreen {
    /// Cancels any in-flight task with the same `id` before scheduling the
    /// new one — preserves the prior named-state contract that firing the
    /// same trigger twice doesn't leave two delayed actions racing.
    private func scheduleDelayedTask(
        _ id: DelayedTaskID,
        after delay: Duration,
        action: @MainActor @escaping () -> Void
    ) {
        delayedTasks[id]?.cancel()
        delayedTasks[id] = delayedTask(after: delay, action: action)
    }

    func cancelDelayedTasks() {
        delayedTasks.values.forEach { $0.cancel() }
        delayedTasks.removeAll()
    }
}

#Preview {
    HomeScreen(showingVaultSelector: false)
        .environmentObject(VaultDetailViewModel())
        .environmentObject(AppViewModel())
}
