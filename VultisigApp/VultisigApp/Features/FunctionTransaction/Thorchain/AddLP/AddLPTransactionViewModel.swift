//
//  AddLPTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//
//  A liquidity deposit, from either entry point: an existing position opened
//  from the DeFi tab, or a chain's action list where the user picks the pool
//  first and the asset follows.
//
//  Three properties are load-bearing here, and the form this replaces got all
//  three wrong.
//
//  • **The destination is resolved for the asset in hand, when the transaction
//    is made.** The old form resolved it once on load and never again, while
//    its pool dropdown went on reassigning the source asset underneath — so a
//    native→ERC-20 switch approved the inbound vault as an ERC-20 spender, and
//    an ERC-20→native switch signed a plain transfer to the router contract.
//    Every path that changes the asset invalidates the answer, and the answer
//    carries the asset it was resolved for so a stale one cannot be spent.
//  • **The amount is parsed strictly.** `NumberFormatter` reinterprets a
//    separator from the other convention instead of refusing it, and on a
//    deposit that is a ten-times send from a paste.
//  • **Submission is judged on the fields, not on the published aggregate.**
//    `Form.setupForm()` republishes `validForm` a run-loop turn late, so the
//    aggregate can still say `false` for a form that is valid — or `true` for
//    one whose validators were installed after the first emission.
//

import Combine
import Foundation
import OSLog

private let logger = Log.send.viewModel

@MainActor
final class AddLPTransactionViewModel: ObservableObject, Form {

    /// How the pool is decided.
    enum PoolSource: Equatable {
        /// An existing position: the pool is fixed, and the asset with it.
        case fixed(pool: String?)
        /// No position yet — the user picks from the chain's pools, and the
        /// asset deposited follows that choice.
        case chosen
    }

    /// What the app knows about the pools offered on this chain.
    enum PoolsState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    /// The pool list this form offers. A closure rather than a service so the
    /// selection rules can be driven without a network.
    typealias PoolsFetch = () async throws -> [ThorchainPool]

    let vault: Vault
    /// Whose pools this deposit joins — `.thorChain` or `.mayaChain`. Decides
    /// where the memo is signed and, for an L1-side deposit, whose inbound
    /// vault receives the funds.
    let protocolChain: Chain
    let poolSource: PoolSource

    /// The asset being deposited.
    ///
    /// Reassigned when the user picks a different pool. Everything derived from
    /// it — the destination, the balance ceiling, the approval notice — is
    /// recomputed rather than remembered, which is the fix this migration
    /// exists for.
    @Published private(set) var coin: Coin
    /// The address credited on the other side of the pool, or nil for a
    /// MayaChain deposit, which takes no paired address.
    @Published private(set) var pairedAddress: String?
    @Published private(set) var pools: [THORChainAsset] = []
    @Published private(set) var poolsState: PoolsState = .idle
    @Published private(set) var selectedPool: THORChainAsset?
    @Published private(set) var destination: LPDepositDestination = .unresolved

    @Published var validForm: Bool = false
    @Published var amountField = FormField(label: "amount".localized)
    @Published var percentageSelected: Double?
    @Published var isLoading: Bool = false
    @Published private(set) var isEnablingThorchain: Bool = false

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?

    private let resolveInboundAddresses: ThorchainLPDestinationResolver.InboundAddressFetch
    private let fetchPools: PoolsFetch
    /// Locale the amount is read in. Injected so a test pins the separators
    /// rather than inheriting the machine's — the parse deliberately refuses an
    /// amount written in another locale's convention, so which locale is in
    /// force is part of the behaviour under test.
    private let locale: Locale

    /// Monotonic stamp identifying the newest destination read. A load-time
    /// probe and a Continue-tap read can be in flight together, and a response
    /// that has already resolved cannot be cancelled — so this, not a
    /// `cancel()`, is what keeps the state showing the newest answer rather
    /// than the last-to-arrive one.
    private var destinationGeneration: UInt64 = 0
    private var destinationTask: Task<Void, Never>?
    private var poolsTask: Task<Void, Never>?

    init(
        coin: Coin,
        pairedCoin: Coin?,
        protocolChain: Chain,
        poolSource: PoolSource,
        vault: Vault,
        prefillsFullBalance: Bool,
        resolveInboundAddresses: @escaping ThorchainLPDestinationResolver.InboundAddressFetch
            = ThorchainLPDestinationResolver.live,
        fetchPools: @escaping PoolsFetch = { try await ThorchainService.shared.fetchLPPools() },
        locale: Locale = .current
    ) {
        self.coin = coin
        self.protocolChain = protocolChain
        self.poolSource = poolSource
        self.vault = vault
        self.resolveInboundAddresses = resolveInboundAddresses
        self.fetchPools = fetchPools
        self.locale = locale
        // MayaChain credits the depositing address itself, so a paired address
        // would name an account the memo has no slot for.
        self.pairedAddress = protocolChain == .mayaChain ? nil : pairedCoin?.address
        self.percentageSelected = prefillsFullBalance ? 100 : nil
        // NOT `prefillsFullBalance`. A pre-filled 100% is a convenience, not a
        // send-max: `sendMaxAmount` changes how a UTXO transaction is planned
        // and what it sweeps, and the form this replaces only ever set it from
        // a percentage the user tapped. Seeding it here would have silently
        // turned every DeFi-tab deposit into a max send.
        self.isMaxAmount = false
    }

    deinit {
        destinationTask?.cancel()
        poolsTask?.cancel()
    }

    // MARK: - Entry points

    /// A deposit into an existing position, from the DeFi tab.
    ///
    /// `side` says which of the position's two assets is deposited. Positions
    /// put the protocol's own asset in `coin1`, so `.coin1` is the deposit the
    /// tab has always made and `.coin2` is the L1 side.
    static func position(
        coin1: Coin,
        coin2: Coin,
        side: LPDepositSide,
        position: LPPosition,
        vault: Vault
    ) -> AddLPTransactionViewModel {
        AddLPTransactionViewModel(
            coin: side == .coin1 ? coin1 : coin2,
            pairedCoin: side == .coin1 ? coin2 : coin1,
            // The pool belongs to whichever protocol holds the position, and
            // that is `coin1`'s chain whichever side is being deposited.
            protocolChain: coin1.chain,
            poolSource: .fixed(pool: position.poolName),
            vault: vault,
            prefillsFullBalance: true
        )
    }

    /// A deposit opened from a chain's action list, where no position exists
    /// yet and the pool is the first thing the user chooses.
    static func chain(coin: Coin, vault: Vault) -> AddLPTransactionViewModel {
        AddLPTransactionViewModel(
            coin: coin,
            pairedCoin: vault.nativeCoin(for: .thorChain),
            protocolChain: .thorChain,
            poolSource: .chosen,
            vault: vault,
            // Deliberately not seeded. The chain's own gas asset pays the fee
            // out of the same balance, so a pre-filled 100% is an amount that
            // can never be signed — and unlike a position deposit, the asset
            // here is not chosen yet when the form opens.
            prefillsFullBalance: false
        )
    }

    // MARK: - Lifecycle

    func onLoad() {
        // Installed before `setupForm()`: the shared pipeline validates on the
        // field's first emission, so a validator added afterwards would let a
        // pristine form publish `valid`.
        amountField.validators = [
            ClosureValidator { [weak self] value in
                guard let self else { return }
                guard let amount = HumanDecimalAmount.parse(
                    value,
                    decimals: self.coin.decimals,
                    locale: self.locale
                ) else {
                    throw HelperError.runtimeError("invalidAmount".localized)
                }
                guard amount > 0 else {
                    throw HelperError.runtimeError("amountCannotBeZero".localized)
                }
                guard amount <= self.coin.balanceDecimal else {
                    throw HelperError.runtimeError("amountExceeded".localized)
                }
            }
        ]
        setupForm()

        switch poolSource {
        case .fixed:
            // The asset is already known, so the destination can be probed for
            // display. The transaction takes the answer fetched on the tap.
            probeDestination()
        case .chosen:
            loadPools()
        }
    }

    // MARK: - Pools

    /// A THORChain pool credits liquidity to a RUNE account, which the memo has
    /// to name — so a vault that holds no RUNE cannot deposit into one at all.
    var isThorchainEnabled: Bool {
        protocolChain != .thorChain || vault.nativeCoin(for: .thorChain) != nil
    }

    /// Adds RUNE to the vault so a THORChain deposit can name a paired address.
    ///
    /// Carried over from the form this replaces, where it was the only way out
    /// of an otherwise unsubmittable screen. The paired address is re-read
    /// afterwards because it is what the new coin supplies.
    func enableThorchain() async {
        guard !isEnablingThorchain, !isThorchainEnabled else { return }
        guard let runeMeta = TokensStore.TokenSelectionAssets.first(where: {
            $0.chain == .thorChain && $0.isNativeToken
        }) else { return }

        isEnablingThorchain = true
        defer { isEnablingThorchain = false }

        do {
            try await CoinService.addToChain(assets: [runeMeta], to: vault)
        } catch {
            logger.error("Failed to enable THORChain for LP: \(error.localizedDescription, privacy: .public)")
            return
        }

        pairedAddress = vault.nativeCoin(for: .thorChain)?.address
    }

    /// Whether the form shows a pool picker at all.
    var showsPoolPicker: Bool {
        poolSource == .chosen
    }

    /// The pool the memo names, or nil until one is chosen.
    var poolName: String? {
        switch poolSource {
        case .fixed(let pool):
            return pool?.nilIfEmpty
        case .chosen:
            return selectedPool?.thorchainAsset
        }
    }

    func loadPools() {
        poolsTask?.cancel()
        poolsState = .loading
        // `self` is captured weakly and reacquired only AFTER the read. The
        // task is stored on `self`, so holding a strong reference across the
        // await would keep the view model alive for exactly as long as the
        // request hangs — which is the case `deinit`'s cancellation exists for.
        let fetch = fetchPools
        poolsTask = Task { @MainActor [weak self] in
            do {
                let fetched = try await fetch()
                guard !Task.isCancelled, let self else { return }
                self.pools = ThorchainLPPoolCatalog.depositablePools(
                    on: self.coin.chain,
                    pools: fetched,
                    holdings: self.vault.coins
                )
                self.poolsState = .loaded
                // A chain with a single depositable pool has nothing to ask.
                if self.pools.count == 1, let only = self.pools.first {
                    self.select(pool: only)
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                logger.error("Failed to load THORChain LP pools: \(error.localizedDescription, privacy: .public)")
                self.pools = []
                self.poolsState = .failed
            }
        }
    }

    /// Picks a pool, and with it the asset the deposit moves.
    ///
    /// Every destination-shaped answer is thrown away here. That is the fix:
    /// the recipient of a native transfer is the inbound vault and the
    /// recipient of an ERC-20 one is the router, so an answer resolved for the
    /// previous asset is not merely stale, it is the wrong kind of address.
    func select(pool: THORChainAsset) {
        selectedPool = pool
        guard let depositCoin = ThorchainLPPoolCatalog.depositCoin(
            forPool: pool.thorchainAsset,
            in: vault.coins
        ) else {
            // Unreachable: the list is built from coins the vault holds. If it
            // ever happens, invalidating rather than keeping the previous asset
            // is what stops a memo naming one pool being paid for by another.
            invalidateDestination()
            return
        }

        guard depositCoin.toCoinMeta() != coin.toCoinMeta() else { return }

        coin = depositCoin
        // The amount was typed against a different asset's balance and a
        // different ticker; carrying the digits over would silently re-denominate
        // them.
        amountField.value = .empty
        percentageSelected = nil
        isMaxAmount = false
        invalidateDestination()
        probeDestination()
    }

    // MARK: - Destination

    /// Drops any resolved destination, leaving the form in the state it opened
    /// in rather than in a failed one.
    func invalidateDestination() {
        destinationTask?.cancel()
        destinationTask = nil
        destinationGeneration &+= 1
        destination = .unresolved
    }

    /// Display-only read. The transaction never uses this answer; it takes the
    /// one fetched on the tap.
    private func probeDestination() {
        let generation = nextDestinationGeneration()
        let asset = coin
        let chain = protocolChain
        let fetch = resolveInboundAddresses
        // Weak, and reacquired only after the read — see `loadPools()`.
        destinationTask = Task { @MainActor [weak self] in
            let resolved = await ThorchainLPDestinationResolver.resolve(
                depositing: asset,
                into: chain,
                bypassCache: false,
                fetch: fetch
            )
            self?.publish(resolved, resolvedFor: asset, generation: generation)
        }
    }

    /// Publishes a resolution, or drops it.
    ///
    /// Two guards, because two different things can have moved while the read
    /// was in flight: a newer read may have been started, and the pool picker
    /// may have changed the asset. Either makes this answer one that must not
    /// be published.
    private func publish(_ resolved: LPDepositDestination, resolvedFor asset: Coin, generation: UInt64) {
        guard generation == destinationGeneration, asset.toCoinMeta() == coin.toCoinMeta() else { return }
        destination = resolved
    }

    private func nextDestinationGeneration() -> UInt64 {
        destinationGeneration &+= 1
        return destinationGeneration
    }

    private func resolveDestination(bypassCache: Bool, generation: UInt64) async {
        let asset = coin
        let resolved = await ThorchainLPDestinationResolver.resolve(
            depositing: asset,
            into: protocolChain,
            bypassCache: bypassCache,
            fetch: resolveInboundAddresses
        )
        publish(resolved, resolvedFor: asset, generation: generation)
    }

    // MARK: - Building

    /// Resolves the live destination, then builds. This is the Continue path.
    ///
    /// The recipient is fetched here with the cache bypassed, so the address
    /// the transaction carries is the one THORChain is observing at the moment
    /// the transaction is made — not the one that happened to be cached when
    /// the form opened, and not one resolved for an asset the user has since
    /// replaced. It re-reads the LP-actions pause flag in the same breath,
    /// which narrows (though it does not close) the window in which a route
    /// halts between here and signing.
    func prepareTransactionBuilder() async -> TransactionBuilder? {
        guard !isLoading else { return nil }

        validateErrors()
        guard form.allSatisfy({ $0.valid }), poolName != nil else { return nil }

        isLoading = true
        defer { isLoading = false }

        destinationTask?.cancel()
        destinationTask = nil
        await resolveDestination(bypassCache: true, generation: nextDestinationGeneration())

        return transactionBuilder
    }

    var transactionBuilder: TransactionBuilder? {
        // `validateErrors()` re-runs every field's validators synchronously and
        // writes the answer to `field.valid`, so the fields — not the published
        // `validForm` — are what this turn's submission is judged on. The
        // aggregate is republished a run-loop turn late, and reading it here
        // would be wrong in both directions.
        validateErrors()
        guard form.allSatisfy({ $0.valid }) else { return nil }
        // A THORChain pool without a paired RUNE account is a memo for a
        // DIFFERENT operation — `+:POOL` alone is an asymmetric, asset-only
        // deposit — so an absent RUNE coin blocks rather than silently changing
        // what is signed.
        guard isThorchainEnabled else { return nil }
        guard let poolName else { return nil }
        guard let amount = HumanDecimalAmount.parse(
            amountField.rawValue,
            decimals: coin.decimals,
            locale: locale
        ), amount > 0, amount <= coin.balanceDecimal else {
            return nil
        }
        // Nil, not empty: a protocol-native deposit legitimately names no
        // recipient, so emptiness cannot stand in for "unresolved" here.
        guard let toAddress = destination.depositAddress(for: coin) else { return nil }

        return AddLPTransactionBuilder(
            coin: coin,
            amount: amount.formatToDecimal(digits: coin.decimals),
            poolName: poolName,
            pairedAddress: pairedAddress,
            sendMaxAmount: isMaxAmount,
            toAddress: toAddress
        )
    }

    // MARK: - Form chrome

    var title: String {
        String(format: "addCoinLP".localized, coin.chain.name)
    }

    /// The two-transaction notice an ERC-20 deposit needs.
    var showsApprovalInfo: Bool {
        destination.requiresApproval
    }

    var showAsymmetricDepositInfo: Bool {
        protocolChain == .mayaChain
    }

    var asymmetricDepositMessage: String {
        "asymmetricDepositInfo".localized
    }

    /// Whether the pool list is still arriving.
    var isLoadingPools: Bool {
        showsPoolPicker && (poolsState == .idle || poolsState == .loading)
    }

    /// Whether the pool list failed and can be asked for again.
    var canRetryPools: Bool {
        showsPoolPicker && poolsState == .failed
    }

    /// Why the deposit cannot proceed, or nil when nothing is wrong.
    var blockingMessage: String? {
        if !isThorchainEnabled {
            return "thorChainNotEnabledForLP".localized
        }
        if case .chosen = poolSource, poolsState == .loaded, pools.isEmpty {
            return "addLpNoDepositablePools".localized
        }
        if case .chosen = poolSource, poolsState == .failed {
            return "failedToLoadPools".localized
        }
        return destination.message
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
