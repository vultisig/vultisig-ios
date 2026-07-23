//
//  ChainDetailScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import SwiftUI

struct ChainDetailScreen: View {
    @Environment(\.router) var router
    let nativeCoin: Coin
    let vault: Vault
    @Binding var refreshTrigger: Bool
    var onAddressCopy: ((Coin) -> Void)?

    @StateObject var viewModel: ChainDetailViewModel
    /// Drives the QBTC banner / Claim button visibility based on the
    /// vault's BTC address actually having claimable UTXOs. Same checker
    /// is used on both `.bitcoin` and `.qbtc` chain detail screens.
    @StateObject private var qbtcEligibility: QBTCClaimEligibilityChecker
    @State var showManageTokens: Bool = false
    @State var showSearchHeader: Bool = false
    @State var coinToShow: Coin?
    @State var showCoinDetail: Bool = false
    @State var focusSearch: Bool = false
    @State var showReceiveSheet: Bool = false
    @State var scrollProxy: ScrollViewProxy?
    /// Set when the user taps the QBTC promo banner without an MLDSA
    /// key — pickup happens once `qbtcQuantumKeygenCompleted` fires so the
    /// user lands back here with QBTC already added to the vault.
    @State private var pendingQbtcAddAfterKeygen: Bool = false
    @State private var addressCopyTask: Task<Void, Never>?
    @State private var coinDetailTask: Task<Void, Never>?

    private let scrollReferenceId = "chainDetailScreenBottomContentId"

    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @Environment(\.dismiss) var dismiss

    var coins: [Coin] {
        vault.coins(for: nativeCoin.chain)
    }

    private var hasMLDSAKey: Bool {
        let key = vault.publicKeyMLDSA44
        return key != nil && !(key?.isEmpty ?? true)
    }

    private var hasQbtcChain: Bool {
        vault.coins.contains { $0.chain == .qbtc }
    }

    /// QBTC promo banner is visible on the BTC chain detail screen when
    /// the vault's BTC address has at least one claimable UTXO. This is
    /// now independent of whether the QBTC chain is already enabled on
    /// the vault — the eligibility checker drives both branches. Hidden
    /// entirely when `QBTCConfig.isFeatureEnabled` is `false`.
    private var showsQbtcBanner: Bool {
        QBTCConfig.isFeatureEnabled
            && nativeCoin.chain == .bitcoin
            && qbtcEligibility.hasClaimableUtxos
    }

    /// QBTC chain detail's Claim button mirrors the same predicate: only
    /// show it when there's actually something to claim. Hides the
    /// 96pt reserved padding too so the list flows full-bleed otherwise.
    /// Hidden entirely when `QBTCConfig.isFeatureEnabled` is `false`.
    private var showsQbtcClaimButton: Bool {
        QBTCConfig.isFeatureEnabled
            && nativeCoin.chain == .qbtc
            && qbtcEligibility.hasClaimableUtxos
    }

    /// Bottom clearance for the Claim button. macOS / iPadOS / iOS<26
    /// use the legacy `VultiTabBar` overlay — its top edge sits at
    /// roughly `40pt` (tab bar padding) + `64pt` (height) ≈ 104pt above
    /// the screen edge, so the CTA needs to clear that plus a little
    /// breathing room. iPhone iOS 26+ uses the system glass `TabView`
    /// which already insets content.
    private var claimButtonBottomInset: CGFloat {
        #if os(macOS)
        return 120
        #else
        if #available(iOS 26.0, *), !isIPadOS {
            return 16
        }
        return 120
        #endif
    }

    /// Bottom padding the scroll content reserves so its last row isn't
    /// hidden under the Claim button overlay. Matches the button's
    /// bottom inset + the button height (~64pt) + small breathing room.
    private var claimButtonReservedHeight: CGFloat {
        claimButtonBottomInset + 80
    }

    init(
        nativeCoin: Coin,
        vault: Vault,
        refreshTrigger: Binding<Bool> = .constant(false),
        onAddressCopy: ((Coin) -> Void)? = nil
    ) {
        self.nativeCoin = nativeCoin
        self.vault = vault
        self._refreshTrigger = refreshTrigger
        self.onAddressCopy = onAddressCopy
        self._viewModel = StateObject(wrappedValue: ChainDetailViewModel(vault: vault, nativeCoin: nativeCoin))
        self._qbtcEligibility = StateObject(wrappedValue: QBTCClaimEligibilityChecker())
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    topContentSection
                        .padding(.top, isMacOS ? 60 : 0)
                    bottomContentSection
                }
                .padding(.bottom, showsQbtcClaimButton ? claimButtonReservedHeight : 0)
                .padding(.horizontal, 16)
                .padding(.bottom, isMacOS ? 120 : 0)
            }
            .onLoad {
                scrollProxy = proxy
            }
        }
        .refreshable {
            refresh()
        }
        .overlay(alignment: .bottom) {
            if showsQbtcClaimButton {
                PrimaryButton(title: "claim".localized) {
                    navigateToAction(action: .qbtcClaim(vault: vault))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, claimButtonBottomInset)
            }
        }
        .background(MainBackgroundWithNotification())
        .crossPlatformSheet(isPresented: $showReceiveSheet) {
            ReceiveQRCodeBottomSheet(
                coin: nativeCoin,
                isNativeCoin: true,
                onClose: { showReceiveSheet = false },
                onShare: { showReceiveSheet = false },
                onCopy: { coin in
                    showReceiveSheet = false
                    addressCopyTask?.cancel()
                    addressCopyTask = delayedTask(after: .milliseconds(350)) {
                        onAddressCopy?(coin)
                    }
                }
            )
        }
        .crossPlatformSheet(isPresented: $showManageTokens) {
            TokenSelectionContainerScreen(
                vault: vault,
                chain: nativeCoin.chain,
                isPresented: $showManageTokens
            )
        }
        .onLoad {
            viewModel.refresh()

            refresh()
        }
        .onChange(of: refreshTrigger) { _, _ in
            refresh()
        }
        .crossPlatformSheet(isPresented: $showCoinDetail) {
            if let coin = coinToShow {
                CoinDetailScreen(
                    coin: coin,
                    vault: vault,
                    isPresented: $showCoinDetail,
                    onCoinAction: onCoinAction
                )
            }
        }
        .onChange(of: coinToShow) { _, newValue in
            if newValue != nil {
                #if os(macOS)
                // Add a small delay on macOS to prevent state conflicts
                coinDetailTask?.cancel()
                coinDetailTask = delayedTask(after: .milliseconds(50)) {
                    showCoinDetail = true
                }
                #else
                showCoinDetail = true
                #endif
            } else {
                coinDetailTask?.cancel()
                showCoinDetail = false
            }
        }
        .onChange(of: showCoinDetail) { _, isShowing in
            if !isShowing {
                coinToShow = nil
            }
        }
        .onChange(of: coins) { _, _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .qbtcQuantumKeygenCompleted)) { note in
            handleQuantumKeygenCompleted(note: note)
        }
        .onDisappear {
            addressCopyTask?.cancel()
            coinDetailTask?.cancel()
        }
    }

    var topContentSection: some View {
        VStack(spacing: 32) {
            ChainDetailHeaderView(
                vault: vault,
                nativeCoin: nativeCoin,
                coins: viewModel.tokens,
                onCopy: onCopy
            )
            CoinActionsView(
                actions: viewModel.availableActions,
                onAction: onAction
            )

            ClaimQbtcPromoBanner(onClaim: onClaimBannerTapped)
                .showIf(showsQbtcBanner)

            TronResourcesCardView(
                availableBandwidth: viewModel.tronLoader?.availableBandwidth ?? 0,
                totalBandwidth: viewModel.tronLoader?.totalBandwidth ?? 0,
                availableEnergy: viewModel.tronLoader?.availableEnergy ?? 0,
                totalEnergy: viewModel.tronLoader?.totalEnergy ?? 0,
                isLoading: viewModel.tronLoader?.isLoading ?? false
            ).showIf(viewModel.isTron)
        }
    }

    var bottomContentSection: some View {
        LazyVStack(spacing: 0) {
            Group {
                if showSearchHeader {
                    searchBottomSectionHeader
                } else {
                    defaultBottomSectionHeader
                }
            }
            .transition(.opacity)
            .frame(height: 42)
            .padding(.bottom, 16)

            ChainDetailListView(viewModel: viewModel) {
                coinToShow = $0
            } onManageTokens: {
                showManageTokens = true
            }
            .background(
                // Reference to scroll when search gets presented
                VStack {}
                    .frame(height: 300)
                    .id(scrollReferenceId)
            )
        }
    }

    var defaultBottomSectionHeader: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                Text("tokens".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Rectangle()
                    .fill(Theme.colors.primaryAccent4)
                    .frame(height: 2)
            }
            .fixedSize()
            Spacer()
            CircularAccessoryIconButton(icon: .magnifier) {
                toggleSearch()
            }
            CircularAccessoryIconButton(icon: .housePen, type: .secondary) {
                showManageTokens = true
            }
        }
    }

    var searchBottomSectionHeader: some View {
        HStack(spacing: 12) {
            SearchTextField(value: $viewModel.searchText, isFocused: $focusSearch)
            Button(action: clearSearch) {
                Text("cancel".localized)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodySMedium)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }
}

private extension ChainDetailScreen {

    func refresh() {
        Task {
            await updateBalances()
            await MainActor.run {
                coinSelectionViewModel.setData(for: vault)
                // Notify viewModel and group to update the tokens list
                viewModel.objectWillChange.send()
            }
            if viewModel.isTron {
                await MainActor.run { viewModel.tronLoader?.load() }
            }
        }
        refreshQbtcEligibility()
    }

    /// Kicks the QBTC eligibility check on entry / pull-to-refresh for
    /// both `.bitcoin` and `.qbtc` chain detail screens. No-ops on other
    /// chains so we don't fire network calls speculatively. Also no-ops
    /// when the QBTC feature flag is off — flag-off users shouldn't burn
    /// network budget on the eligibility check since the banner / button
    /// it drives are hidden anyway.
    func refreshQbtcEligibility() {
        guard QBTCConfig.isFeatureEnabled else { return }
        guard nativeCoin.chain == .bitcoin || nativeCoin.chain == .qbtc else { return }
        let vaultPubKey = vault.pubKeyECDSA
        let supportsClaim = vault.supportsQbtcClaim
        Task { @MainActor in
            guard let btcCoin = viewModel.qbtcClaimBitcoinCoin() else { return }
            await qbtcEligibility.check(
                btcCoin: btcCoin,
                vaultPubKeyECDSA: vaultPubKey,
                vaultSupportsClaim: supportsClaim
            )
        }
    }

    func updateBalances() async {
        let vault = self.vault // Capture on main actor
        let coins = vault.coins.filter { $0.chain == nativeCoin.chain }
        await withTaskGroup(of: Void.self) { taskGroup in
            for coin in coins {
                taskGroup.addTask {
                    await coinSelectionViewModel.loadData(coin: coin)
                    if coin.isNativeToken {
                        await CoinService.addDiscoveredTokens(nativeToken: coin, to: vault)
                    }
                }
            }
        }
    }

    func toggleSearch() {
        withAnimation(.interpolatingSpring) {
            showSearchHeader.toggle()
        }

        if showSearchHeader {
            focusSearch.toggle()
        }
    }

    func clearSearch() {
        viewModel.searchText = ""
        toggleSearch()
    }

    func onAction(_ action: CoinAction) {
        var vaultAction: VaultAction?
        switch action {
        case .receive:
            showReceiveSheet = true
            return
        case .send:
            vaultAction = .send(coin: nativeCoin, hasPreselectedCoin: false)
        case .swap:
            guard let fromCoin = viewModel.tokens.first else { return }
            vaultAction = .swap(fromCoin: fromCoin)
        case .deposit, .bridge, .memo:
            vaultAction = .function(coin: nativeCoin)
        case .buy:
            vaultAction = .buy(
                address: nativeCoin.address,
                blockChainCode: nativeCoin.chain.banxaBlockchainCode,
                coinType: nativeCoin.ticker
            )
        case .sell:
            break
        }

        guard let vaultAction else { return }

        navigateToAction(action: vaultAction)
    }

    func onCopy() {
        onAddressCopy?(nativeCoin)
    }

    func onCoinAction(_ action: VaultAction) {
        coinToShow = nil
        navigateToAction(action: action)
    }

    func navigateToAction(action: VaultAction) {
        router.navigate(to: HomeRoute.vaultAction(action: action, vault: vault))
    }

    func onClaimBannerTapped() {
        if hasMLDSAKey {
            navigateToAction(action: .qbtcClaim(vault: vault))
        } else {
            pendingQbtcAddAfterKeygen = true
            router.navigate(to: KeygenRoute.quantumSecurityIntro(vault: vault))
        }
    }

    func handleQuantumKeygenCompleted(note: Notification) {
        guard QBTCConfig.isFeatureEnabled else { return }
        guard pendingQbtcAddAfterKeygen else { return }
        let completedPubKey = note.userInfo?[QuantumKeygenNotification.vaultPubKeyECDSAKey] as? String
        guard completedPubKey == vault.pubKeyECDSA else { return }
        pendingQbtcAddAfterKeygen = false
        guard let qbtcAsset = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .qbtc && $0.isNativeToken }) else {
            return
        }
        Task { @MainActor in
            let currentSelection = Set(vault.coins.map { $0.toCoinMeta() })
            await CoinService.saveAssets(
                for: vault,
                selection: currentSelection.union([qbtcAsset])
            )
            refresh()
            // Auto-continue into the claim flow after the QBTC chain is
            // attached — matches Figma spec where tapping the BTC banner
            // without a quantum key still ends up on the claim screen.
            navigateToAction(action: .qbtcClaim(vault: vault))
        }
    }
}

#Preview {
    ChainDetailScreen(
        nativeCoin: .example,
        vault: .example
    )
    .environmentObject(HomeViewModel())
}
