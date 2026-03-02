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
    @State private var deeplinkError: Error?

    @State private var capturedGeometryHeight: CGFloat = 600

    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var phoneCheckUpdateViewModel: PhoneCheckUpdateViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) var openURL
    var tabs: [HomeTab] {
        !(appViewModel.selectedVault?.availableDefiChains.isEmpty ?? true) ? [.wallet, .defi] : [.wallet]
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
        .withDeeplinkRouter(
            vaultRoute: $vaultRoute,
            showScanner: $showScanner,
            showVaultSelector: $showVaultSelector,
            deeplinkError: $deeplinkError,
            sendTx: sendTx,
            vaults: vaults
        )
        .alert(
            NSLocalizedString("newUpdateAvailable", comment: ""),
            isPresented: $phoneCheckUpdateViewModel.showUpdateAlert
        ) {
            Link(destination: StaticURL.AppStoreVultisigURL) {
                Text(NSLocalizedString("updateNow", comment: ""))
            }

            #if os(macOS)
            Link(destination: StaticURL.GitHubReleasesURL) {
                Text(NSLocalizedString("downloadViaWebsite", comment: ""))
            }
            #endif

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
                            NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
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
                    if deeplinkViewModel.pendingSendDeeplink || deeplinkViewModel.pendingConnectDeeplink {
                        NotificationCenter.default.post(name: NSNotification.Name("DeeplinkVaultSelection"), object: vault)
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
        // Delay navigation to let vault selector sheet dismiss fully
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let vault = appViewModel.selectedVault else { return }
            router.navigate(to: KeygenRoute.joinKeysign(vault: vault))
        }
    }

    fileprivate func checkUpdate() {
        phoneCheckUpdateViewModel.checkForUpdates(isAutoCheck: true)
    }

    fileprivate func moveToCreateVaultView() {
        guard let selectedVault = appViewModel.selectedVault else { return }
        showVaultSelector = false
        // Delay navigation to let vault selector sheet dismiss fully
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            router.navigate(to: OnboardingRoute.joinKeygen(
                vault: Vault(name: "Main Vault"),
                selectedVault: selectedVault
            ))
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

        if deeplinkViewModel.type != nil {
            NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
        }
    }

    fileprivate func onVaultLoaded(vault: Vault) {
        Task { @MainActor in
            await VaultDefiChainsService().enableDefiChainsIfNeeded(for: vault)
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
}

#Preview {
    HomeScreen(showingVaultSelector: false)
        .environmentObject(VaultDetailViewModel())
        .environmentObject(AppViewModel())
}
