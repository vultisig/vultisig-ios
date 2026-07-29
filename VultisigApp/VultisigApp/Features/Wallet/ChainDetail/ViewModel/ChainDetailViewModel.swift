//
//  ChainDetailViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import Combine
import Foundation

/// Main-actor isolated because every stored value it reads is SwiftData `@Model`
/// state — `vault.coins`, each `Coin`'s balance/ticker/`uniqueId`, the native
/// coin's address — which must never be touched off the MainActor. The isolation
/// also matches what the type already is in practice: an `ObservableObject`
/// driving a SwiftUI screen.
@MainActor
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
    /// Monotonic tag identifying the most recent trust-line refresh, so an older
    /// pass that finishes late can't overwrite a newer answer.
    private var trustLineRefreshGeneration: UInt64 = 0

    private var cancellables = Set<AnyCancellable>()

    init(vault: Vault, nativeCoin: Coin, rippleService: RippleService = .shared) {
        self.vault = vault
        self.nativeCoin = nativeCoin
        self.rippleService = rippleService
        self.tronLoader = nativeCoin.chain == .tron ? TronResourcesLoader(address: nativeCoin.address) : nil
        self.tokens = Self.computeTokens(vault: vault, nativeCoin: nativeCoin)

        // Both sinks already receive on the main queue, but a Combine closure
        // carries no actor isolation of its own. `assumeIsolated` states the
        // guarantee the scheduler makes instead of adding a `Task` hop, which
        // would let a publish land after the state it was meant to describe.
        tronLoader?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)

        // Vault publishes once per `coin.rawBalance` write during a refresh —
        // 20+ times per cycle. Debounce so we sort once at the end.
        vault.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.recomputeTokens() }
            }
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
    ///
    /// Refreshes are generation-guarded. Several can be in flight at once (a
    /// balance publish, a pull-to-refresh and a token-list recompute all trigger
    /// one), and without the guard a slower earlier pass could land last and
    /// replace a newer answer with a staler one — resurrecting an `Activate`
    /// button on a line that has since been opened.
    func refreshTrustLineState() {
        guard isRipple else { return }
        let tokens = self.tokens.filter { !$0.isNativeToken }
        guard !tokens.isEmpty else {
            trustLineRefreshGeneration &+= 1
            tokensNeedingTrustLine = []
            return
        }
        trustLineRefreshGeneration &+= 1
        let generation = trustLineRefreshGeneration
        let address = nativeCoin.address
        // Keyed by contract address because that is what the ledger answer is
        // keyed by; mapped back to `uniqueId` for the row lookup.
        let identifiers = Dictionary(
            tokens.map { ($0.contractAddress, $0.uniqueId) },
            uniquingKeysWith: { first, _ in first }
        )
        let metas = tokens.map { $0.toCoinMeta() }
        Task { @MainActor [rippleService] in
            let states = await rippleService.trustLineStates(for: metas, address: address)
            // A newer pass has already answered — discard this one rather than
            // overwrite it.
            guard generation == trustLineRefreshGeneration else { return }
            tokensNeedingTrustLine = Set(
                states
                    .filter { $0.value == .absent }
                    .compactMap { identifiers[$0.key] }
            )
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
