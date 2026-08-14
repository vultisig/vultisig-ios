//
//  SwitchTransactionViewModel.swift
//  VultisigApp
//
//  Cosmos Hub → THORChain SWITCH form view-model: a THORChain address to
//  credit, an amount to move, and a destination the user never sees or types.
//
//  Two properties are load-bearing, and the legacy sub-model got both wrong:
//
//  • The destination is THORChain's inbound vault, which the protocol churns.
//    Legacy resolved it once from a five-minute cache when the form opened and
//    reused it for the life of the screen. Here it is resolved on the Continue
//    tap, cache bypassed, in the same call that produces the builder — nothing
//    can change between the resolution and the transaction.
//  • A halted route was logged and swallowed, leaving an empty destination in
//    an editable field. Here it is a published state with a message on screen,
//    and no non-available state can produce a builder.
//

import Combine
import Foundation

private let logger = Log.send.viewModel

/// The inbound-address read this form depends on. Injected so the route states
/// can be exercised without the network; production passes
/// `ThorchainService.shared`.
protocol ThorchainInboundSource {
    func fetchThorchainInboundAddress(bypassCache: Bool) async -> [InboundAddress]
}

extension ThorchainService: ThorchainInboundSource {}

/// What the app currently knows about THORChain's inbound route for the source
/// chain. Only `.available` can produce a transaction; every other state is
/// something the user is told rather than something they sign through.
enum SwitchRouteState: Equatable {
    case resolving
    case available(inboundAddress: String)
    /// THORChain reports the chain halted, or trading paused globally or for
    /// this chain. A transfer to the vault now risks being stranded.
    case halted(chain: String)
    /// THORChain lists no inbound vault for this chain at all.
    case unsupported(chain: String)
    /// The read itself did not produce a usable answer — transport failure, an
    /// empty list, or a vault row with no address.
    case unavailable
}

@MainActor
final class SwitchTransactionViewModel: ObservableObject, Form {
    /// The source chain's native asset — what THORChain's inbound vault for
    /// that chain credits.
    let coin: Coin
    let vault: Vault

    @Published var validForm: Bool = false
    @Published var thorAddressViewModel: AddressViewModel
    @Published var amountField = FormField(label: "amount".localized)
    @Published var percentageSelected: Double?
    @Published var isLoading: Bool = false
    @Published private(set) var routeState: SwitchRouteState = .resolving

    private(set) lazy var form: [FormField] = [
        thorAddressViewModel.field,
        amountField
    ]

    var formCancellable: AnyCancellable?

    private let inboundSource: ThorchainInboundSource
    /// Locale the amount is read in. Injected so a test pins the separators
    /// rather than inheriting the machine's — the parse deliberately refuses an
    /// amount written in another locale's convention, so which locale is in
    /// force is part of the behaviour under test.
    private let locale: Locale

    /// Monotonic stamp identifying the newest route read. The load-time probe
    /// and the Continue-tap read can be in flight together, and a response that
    /// has already resolved cannot be cancelled — so this, not a `cancel()`, is
    /// what keeps the notice showing the newest answer rather than the
    /// last-to-arrive one.
    private var routeGeneration: UInt64 = 0
    private var routeTask: Task<Void, Never>?

    init(
        coin: Coin,
        vault: Vault,
        inboundSource: ThorchainInboundSource = ThorchainService.shared,
        locale: Locale = .current
    ) {
        self.coin = coin
        self.vault = vault
        self.inboundSource = inboundSource
        self.locale = locale
        // The address book and QR accessories are scoped by this coin, so the
        // THORChain one is used when the vault holds it. Validation does NOT
        // depend on which coin resolved here — `onLoad()` pins the validator to
        // `.thorChain` either way — because a vault without RUNE must still
        // reject a cosmos1… address typed into the field the memo names.
        self.thorAddressViewModel = AddressViewModel(
            label: "thorchainAddress".localized,
            coin: vault.coins.first { $0.chain == .thorChain && $0.isNativeToken } ?? coin
        )
    }

    deinit {
        routeTask?.cancel()
    }

    func onLoad() {
        // Installed before `setupForm()`: the shared pipeline validates on the
        // field's first emission, so a validator added afterwards would let a
        // pristine form publish `valid`.
        thorAddressViewModel.field.validators = [
            // Legacy accepted a THOR *or* Maya *or* TON address here. The memo
            // names a THORChain account and nothing else can be credited, so a
            // maya1… destination was a silent loss.
            AddressValidator(chain: .thorChain),
            RequiredValidator(errorMessage: "emptyAddressField".localized)
        ]
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

        if let thorAddress = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken })?.address {
            thorAddressViewModel.field.value = thorAddress
        }

        // The amount is deliberately NOT seeded. Legacy filled it with the
        // whole balance because its field bound a non-optional `Decimal` and
        // had nowhere empty to sit, but SWITCH moves the chain's own gas asset
        // — the fee comes out of the same balance, so a pre-filled 100% is an
        // amount that can never be signed.

        // Display only. The builder never reads the answer to this read; it
        // takes the one fetched on the tap.
        probeRoute()
    }

    /// Non-nil whenever the route is known not to carry a switch. Rendered above
    /// Continue so a user who cannot proceed is told why, rather than facing a
    /// button that does nothing.
    ///
    /// `.resolving` deliberately says nothing: it is the transient state before
    /// the first answer lands, the form is fully usable during it, and a
    /// Continue tapped while it is in force re-reads the route under the loading
    /// overlay and then reports whatever comes back. A notice there would flash
    /// on every open.
    var routeMessage: String? {
        switch routeState {
        case .resolving, .available:
            return nil
        case .halted(let chain):
            return String(format: "inboundPaused".localized, chain)
        case .unsupported(let chain):
            return String(format: "inboundAddressNotFound".localized, chain)
        case .unavailable:
            return "switchRouteUnavailable".localized
        }
    }

    /// Resolves the live inbound vault, then builds. This is the Continue path:
    /// the destination is fetched here, with the cache bypassed, so the address
    /// the transaction carries is the one THORChain is observing at the moment
    /// the transaction is made — not the one that happened to be cached when
    /// the form opened.
    ///
    /// `routeState` is written synchronously when the read returns and read
    /// synchronously by `transactionBuilder` below, with no suspension between
    /// them, so the load-time probe cannot land in the middle.
    func prepareTransactionBuilder() async -> TransactionBuilder? {
        guard !isLoading else { return nil }

        validateErrors()
        guard form.allSatisfy({ $0.valid }) else { return nil }

        isLoading = true
        defer { isLoading = false }

        routeTask?.cancel()
        routeTask = nil
        await resolveRoute(bypassCache: true, generation: nextRouteGeneration())

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

        guard case .available(let inboundAddress) = routeState, inboundAddress.isNotEmpty else { return nil }

        guard let switchAmount = HumanDecimalAmount.parse(
            amountField.rawValue,
            decimals: coin.decimals,
            locale: locale
        ), switchAmount > 0, switchAmount <= coin.balanceDecimal else {
            return nil
        }

        return SwitchTransactionBuilder(
            coin: coin,
            thorchainAddress: thorAddressViewModel.field.value,
            inboundAddress: inboundAddress,
            switchAmount: switchAmount
        )
    }

    // MARK: - Route

    private func probeRoute() {
        routeState = .resolving
        let generation = nextRouteGeneration()
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            await self?.resolveRoute(bypassCache: false, generation: generation)
        }
    }

    private func nextRouteGeneration() -> UInt64 {
        routeGeneration &+= 1
        return routeGeneration
    }

    private func resolveRoute(bypassCache: Bool, generation: UInt64) async {
        let chainName = ThorchainService.getInboundChainName(for: coin.chain)
        let inbounds = await inboundSource.fetchThorchainInboundAddress(bypassCache: bypassCache)

        // A superseded read never writes: its answer describes a moment that
        // has already been replaced.
        guard generation == routeGeneration else { return }

        guard !inbounds.isEmpty else {
            // `fetchThorchainInboundAddress` is fail-soft and answers with an
            // empty list on a transport or decode failure, so an empty list
            // means "we do not know", never "not halted".
            logger.warning("No THORChain inbound addresses returned; switch route unresolved")
            routeState = .unavailable
            return
        }

        guard let inbound = inbounds.first(where: {
            $0.chain.caseInsensitiveCompare(chainName) == .orderedSame
        }) else {
            routeState = .unsupported(chain: chainName)
            return
        }

        guard !inbound.isTradingHalted else {
            routeState = .halted(chain: inbound.chain)
            return
        }

        guard inbound.address.isNotEmpty else {
            routeState = .unavailable
            return
        }

        routeState = .available(inboundAddress: inbound.address)
    }
}
