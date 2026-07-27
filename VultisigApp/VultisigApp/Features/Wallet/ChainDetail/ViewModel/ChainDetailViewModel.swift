//
//  ChainDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import Combine
import Foundation

final class ChainDetailViewModel: ObservableObject {
    private let nativeCoin: Coin
    private let vault: Vault

    @Published var searchText: String = ""
    @Published var selectedTab: ChainDetailTab = .tokens
    /// Sorted token list for the current chain. Stored (not computed) and
    /// recomputed on a debounced `vault.objectWillChange` signal so a single
    /// balance refresh that mutates N coins doesn't trigger N filter+sort
    /// passes (#4337). Two non-native tokens with similar fiat values would
    /// otherwise swap order on every property publish and read as flicker.
    @Published private(set) var tokens: [Coin] = []

    var tabs: [SegmentedControlItem<ChainDetailTab>] = [
        SegmentedControlItem(value: .tokens, title: "tokens".localized)
    ]

    let actionResolver = CoinActionResolver()

    @Published var availableActions: [CoinAction] = []

    // Tron resources
    let tronLoader: TronResourcesLoader?
    var isTron: Bool { nativeCoin.chain == .tron }

    /// `uniqueId`s of the XRPL issued currencies this account demonstrably holds
    /// NO trust line for — the tokens that need an `Activate` affordance.
    ///
    /// Only coins proven to be missing a line are listed. A state we couldn't
    /// determine is deliberately absent: offering to open a line we have no
    /// evidence is missing would invite a keysign ceremony (and a fee) for
    /// nothing.
    @Published private(set) var tokensNeedingTrustLine: Set<String> = []

    private let rippleService: RippleService
    private var isRipple: Bool { nativeCoin.chain == .ripple }

    private var cancellables = Set<AnyCancellable>()

    init(vault: Vault, nativeCoin: Coin, rippleService: RippleService = .shared) {
        self.vault = vault
        self.nativeCoin = nativeCoin
        self.rippleService = rippleService
        self.tronLoader = nativeCoin.chain == .tron ? TronResourcesLoader(address: nativeCoin.address) : nil
        self.tokens = Self.computeTokens(vault: vault, nativeCoin: nativeCoin)

        tronLoader?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Vault publishes once per `coin.rawBalance` write during a refresh —
        // 20+ times per cycle. Debounce so we sort once at the end.
        vault.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeTokens() }
            .store(in: &cancellables)
    }

    func refresh() {
        Task { @MainActor in
            availableActions = await actionResolver.resolveActions(for: nativeCoin.chain).filtered
        }
        recomputeTokens()
        refreshTrustLineState()
    }

    /// Recomputes which XRPL tokens are missing a trust line.
    ///
    /// Adds NO network traffic: it reads the trust lines the balance refresh
    /// already fetched for this address, so the answer costs nothing per token
    /// row. No-op on every non-XRPL chain.
    func refreshTrustLineState() {
        guard isRipple else { return }
        let tokens = self.tokens.filter { !$0.isNativeToken }
        guard !tokens.isEmpty else {
            tokensNeedingTrustLine = []
            return
        }
        let address = nativeCoin.address
        let identified = tokens.map { (uniqueId: $0.uniqueId, meta: $0.toCoinMeta()) }
        Task { @MainActor [rippleService] in
            var missing: Set<String> = []
            for token in identified {
                if await rippleService.trustLineState(for: token.meta, address: address) == .absent {
                    missing.insert(token.uniqueId)
                }
            }
            tokensNeedingTrustLine = missing
        }
    }

    /// Whether `coin` should render the `Activate` affordance instead of a
    /// balance.
    func needsTrustLine(_ coin: Coin) -> Bool {
        tokensNeedingTrustLine.contains(coin.uniqueId)
    }

    var filteredTokens: [Coin] {
        if searchText.isEmpty {
            return tokens
        } else {
            return tokens.filter {
                $0.ticker.lowercased().contains(searchText.lowercased())
            }
        }
    }

    /// The Bitcoin coin the QBTC claim-eligibility check runs against. On
    /// the Bitcoin chain-detail screen the native coin is itself the BTC
    /// coin; on the QBTC screen it's read from the vault, or derived
    /// in-memory when the Bitcoin chain isn't enabled — so the Claim entry
    /// point still appears for a quantum vault that hasn't added Bitcoin.
    /// Returns nil only on a genuine derivation failure.
    @MainActor
    func qbtcClaimBitcoinCoin() -> Coin? {
        if nativeCoin.chain == .bitcoin {
            return nativeCoin
        }
        if let enabled = vault.nativeCoin(for: .bitcoin) {
            return enabled
        }
        return try? QBTCClaimCoinResolver().resolve(vault: vault, chain: .bitcoin)
    }

    private func recomputeTokens() {
        tokens = Self.computeTokens(vault: vault, nativeCoin: nativeCoin)
        refreshTrustLineState()
    }

    private static func computeTokens(vault: Vault, nativeCoin: Coin) -> [Coin] {
        vault.coins.filter { $0.chain == nativeCoin.chain }
            .filter { !$0.isDefiOnly }
            .uniqueBy { $0.uniqueId }
            .sorted {
                if $0.isNativeToken != $1.isNativeToken {
                    return $0.isNativeToken
                }
                return ($0.balanceInFiatDecimal) > ($1.balanceInFiatDecimal)
            }
    }
}
