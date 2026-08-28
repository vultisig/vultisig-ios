//
//  SecuredWithdrawTransactionViewModel.swift
//  VultisigApp
//
//  THORChain secured-asset redemption (`SECURE-`) form view-model: the user
//  picks one of the secured assets the vault actually holds, an amount, and the
//  L1 address the protocol pays out to.
//
//  Two things here are load-bearing beyond the usual form plumbing.
//
//  The destination is validated against the secured asset's OWN chain — a
//  secured BTC redemption pays out to a Bitcoin address, not a THORChain one —
//  so the address validator is rebuilt every time the picker changes. The
//  legacy form accepted any string over ten characters, which is no validation
//  of an unrecoverable payout at all.
//
//  And the outbound-fee floor is a validator on the amount field rather than a
//  bespoke predicate, refreshed under a generation stamp so a slow reply for a
//  previously selected asset can no longer land on the current one.
//

import Combine
import Foundation
import OSLog

private let logger = Log.send.viewModel

/// Serves an already-fetched list to the shared asset picker. The universe here
/// is the vault's own held balances, which this view-model fetches once because
/// it also needs the persisted `Coin` behind each denom — something the
/// picker's `CoinMeta` cannot carry — so the picker must not fetch again.
struct SecuredAssetSelectionDataSource: AssetSelectionDataSource {
    let assets: [THORChainAsset]

    // swiftlint:disable:next async_without_await
    func fetchAssets() async -> [THORChainAsset] { assets }
}

/// Where the outbound-fee floor stands for the current selection.
///
/// Collapsing this to a single `Decimal` is what makes the guard bypassable:
/// "the node has not answered yet" and "the node has no floor for this asset"
/// are both zero, and they have to block in opposite directions. Pending must
/// refuse — the floor may still land above the amount already typed, and there
/// is no second check at sign time.
enum OutboundFeeThreshold: Equatable {
    /// No asset selected, or the selection cannot be priced at all (the vault
    /// holds no coin on the payout chain to value the fee against).
    case notApplicable
    /// A request is in flight for the current selection.
    case pending
    /// The node answered with a floor, in units of the selected secured asset.
    case known(Decimal)
    /// The node has no inbound row for the chain, or neither side has a usable
    /// price. Fails OPEN, deliberately: this is the only route out of a secured
    /// position, so an unreachable endpoint must not read as "you cannot exit".
    case unavailable
}

@MainActor
final class SecuredWithdrawTransactionViewModel: ObservableObject, Form {
    /// THORChain's native asset. Not what gets redeemed: it is the account
    /// whose bank balances carry the secured denoms, and the chain whose
    /// service answers for them.
    let coin: Coin
    let vault: Vault

    @Published var validForm: Bool = false
    @Published var destinationField: FormField
    @Published var amountField: FormField

    @Published var selectedAsset: THORChainAsset?
    @Published private(set) var availableAssets: [THORChainAsset] = []
    @Published private(set) var isLoadingAssets: Bool = true
    @Published private(set) var loadError: String?

    /// The vault's persisted `Coin` for the selected denom. The builder signs
    /// against this, so it is also the gate: no coin, no transaction.
    @Published private(set) var selectedAssetCoin: Coin?
    /// Where the L1 outbound-fee floor currently stands. Three distinct states,
    /// not a `Decimal` that overloads zero: "still asking" and "there is no
    /// floor" have to behave in opposite directions.
    @Published private(set) var outboundFeeThreshold: OutboundFeeThreshold = .notApplicable
    /// Explains a destination the vault cannot pre-fill. Deliberately not an
    /// error on the field: the user can still paste an address they control,
    /// and this is the only route out of a secured position.
    @Published private(set) var destinationNotice: String?

    /// Smallest redemption that still clears THORChain's L1 outbound fee, in
    /// units of the selected secured asset. Zero means there is no floor to
    /// apply — never "one has not arrived yet", which is `.pending`.
    var minimumWithdrawAmount: Decimal {
        guard case .known(let minimum) = outboundFeeThreshold else { return 0 }
        return minimum
    }

    private(set) lazy var form: [FormField] = [destinationField, amountField]
    var formCancellable: AnyCancellable?

    /// The buffer the legacy form applied over the raw outbound fee, kept
    /// verbatim: the fee is quoted at request time and the payout happens a
    /// block or two later, so a redemption sized at exactly the fee can arrive
    /// worth nothing.
    static let outboundFeeBuffer: Decimal = 1.2

    private let dataSource: SecuredWithdrawDataSource
    /// Held `Coin` per secured asset, keyed by `CoinMeta.uniqueId`.
    private var securedAssetCoins: [String: Coin] = [:]
    private var destinationChain: Chain?
    private var loadTask: Task<Void, Never>?
    private var thresholdTask: Task<Void, Never>?
    /// Bumped on every selection. A threshold reply may only be written by the
    /// generation that asked for it.
    private var thresholdGeneration: UInt64 = 0

    /// `dataSource` is optional rather than defaulted because conforming to a
    /// `@MainActor` protocol infers that isolation onto the live type, and a
    /// default argument is evaluated outside the initializer's isolation.
    init(
        coin: Coin,
        vault: Vault,
        dataSource: SecuredWithdrawDataSource? = nil
    ) {
        self.coin = coin
        self.vault = vault
        self.dataSource = dataSource ?? LiveSecuredWithdrawDataSource()
        self.destinationField = FormField(
            label: "destinationAddress".localized,
            validators: [Self.noAssetSelectedValidator]
        )
        self.amountField = FormField(
            label: "amountToWithdraw".localized,
            placeholder: "enterAmount".localized,
            validators: [Self.noAssetSelectedValidator]
        )
    }

    deinit {
        loadTask?.cancel()
        thresholdTask?.cancel()
    }

    /// Both fields start closed, with the reason spelled out. Nothing about a
    /// redemption can be judged before the asset is named: not the chain the
    /// address must belong to, not the balance, not the fee floor.
    private static var noAssetSelectedValidator: FormFieldValidator {
        ClosureValidator { _ in
            throw HelperError.runtimeError("selectSecuredAssetToWithdraw".localized)
        }
    }

    var assetsDataSource: AssetSelectionDataSource {
        SecuredAssetSelectionDataSource(assets: availableAssets)
    }

    /// `BTC.BTC`, `ETH.USDC` — the L1 chain plus the short symbol. The chain
    /// half is what stops three different USDC redemptions reading alike.
    static func displayName(for asset: THORChainAsset) -> String {
        "\(THORChainHelper.securedAssetChain(coinMeta: asset.asset)).\(asset.asset.ticker.uppercased())"
    }

    var selectedAssetDisplayName: String {
        guard let selectedAsset else { return "selectSecuredAssetToWithdraw".localized }
        return Self.displayName(for: selectedAsset)
    }

    var balanceDescription: String {
        guard let selectedAsset, let assetCoin = selectedAssetCoin else {
            return "selectSecuredAssetToSeeBalance".localized
        }
        return String(
            format: "balanceInParentheses".localized,
            assetCoin.balanceDecimal.formatForDisplay(),
            Self.displayName(for: selectedAsset)
        )
    }

    /// Scopes the address field's paste / scan / address-book accessories to
    /// the payout chain. Falls back to the THORChain account only while no
    /// destination chain is known — validation never depends on this, it is
    /// driven by the field's own validators.
    var destinationCoin: Coin {
        guard let destinationChain, let l1Coin = vault.nativeCoin(for: destinationChain) else {
            return coin
        }
        return l1Coin
    }

    func onLoad() {
        setupForm()
        loadAvailableSecuredAssets()
    }

    func handle(destinationAddressResult: AddressResult?) {
        guard let address = destinationAddressResult?.address else { return }
        destinationField.value = address
    }

    // MARK: - Asset discovery

    func loadAvailableSecuredAssets() {
        loadTask?.cancel()
        isLoadingAssets = true
        loadError = nil

        // Same capture shape as the threshold task: the awaited work runs off
        // captured dependencies, so `self` is only touched once the reply is
        // back and `deinit` can still cancel a request in flight.
        loadTask = Task { [weak self, dataSource, vault, coin] in
            do {
                let assets = try await Self.fetchSecuredAssets(
                    dataSource: dataSource,
                    vault: vault,
                    account: coin
                )
                guard !Task.isCancelled else { return }
                self?.apply(securedAssets: assets)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to fetch THORChain balances: \(error.localizedDescription, privacy: .public)")
                self?.applyEmptyPicker(reason: "noSecuredAssets".localized)
            }
        }
    }

    private static func fetchSecuredAssets(
        dataSource: SecuredWithdrawDataSource,
        vault: Vault,
        account: Coin
    ) async throws -> [(asset: THORChainAsset, coin: Coin)] {
        let balances = try await dataSource.securedAssetBalances(
            address: account.address,
            chain: account.chain
        )

        var held: [(asset: THORChainAsset, coin: Coin)] = []
        for balance in balances where Self.isSecuredDenom(balance.denom) {
            let meta = SecuredAssetMapper.coinMeta(forDenom: balance.denom, chain: account.chain)
            let assetCoin: Coin?
            do {
                // Per denom rather than per fetch: one asset the vault cannot
                // persist must not hide every other position the user could
                // still exit with.
                assetCoin = try CoinService.addIfNeeded(
                    asset: meta,
                    to: vault,
                    priceProviderId: meta.priceProviderId
                )
            } catch {
                logger.warning(
                    "Skipping secured asset \(balance.denom, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                continue
            }
            guard let assetCoin else { continue }

            // Guarded: a `@Model` write publishes even when the value is
            // identical, and this runs against coins the screen is observing.
            if assetCoin.rawBalance != balance.amount {
                assetCoin.rawBalance = balance.amount
            }
            guard assetCoin.balanceDecimal > 0 else { continue }

            held.append((THORChainAsset(thorchainAsset: balance.denom, asset: meta), assetCoin))
        }

        return held.sorted { Self.displayName(for: $0.asset) < Self.displayName(for: $1.asset) }
    }

    /// A secured denom is dash-notation (`btc-btc`, `eth-usdc-0x…`). `rune` is
    /// the native asset and `x/…` denoms are RUJI-family tokens, neither of
    /// which the protocol redeems with `SECURE-`.
    static func isSecuredDenom(_ denom: String) -> Bool {
        let lower = denom.lowercased()
        guard lower != "rune" else { return false }
        guard !lower.hasPrefix("x/") else { return false }
        return lower.contains("-")
    }

    private func apply(securedAssets: [(asset: THORChainAsset, coin: Coin)]) {
        guard !securedAssets.isEmpty else {
            applyEmptyPicker(reason: "noSecuredAssets".localized)
            return
        }
        availableAssets = securedAssets.map { $0.asset }
        securedAssetCoins = Dictionary(
            securedAssets.map { ($0.asset.asset.uniqueId, $0.coin) },
            uniquingKeysWith: { _, latest in latest }
        )
        loadError = nil
        isLoadingAssets = false

        // A reload can retire the asset the user had picked. Re-resolving the
        // selection against the fresh map keeps the coin, the destination chain
        // and the fee floor describing the same thing; dropping a selection the
        // reload no longer offers resets the form rather than leaving it
        // pointing at a position that is gone.
        guard let selectedAsset else { return }
        if securedAssetCoins[selectedAsset.asset.uniqueId] == nil {
            clearSelection()
        } else {
            onAssetSelected()
        }
    }

    private func applyEmptyPicker(reason: String) {
        availableAssets = []
        securedAssetCoins = [:]
        clearSelection()
        loadError = reason
        isLoadingAssets = false
    }

    /// Drops the selection and everything derived from it, including any
    /// outstanding threshold request — `startOutboundFeeThresholdRefresh`
    /// bumps the generation, so a reply already in flight can no longer land.
    private func clearSelection() {
        selectedAsset = nil
        selectedAssetCoin = nil
        destinationChain = nil
        destinationNotice = nil
        destinationField.validators = [Self.noAssetSelectedValidator]
        destinationField.value = .empty
        startOutboundFeeThresholdRefresh()
        refreshAmountValidators()
        revalidate()
    }

    // MARK: - Selection

    func onAssetSelected() {
        guard let selectedAsset else { return }
        selectedAssetCoin = securedAssetCoins[selectedAsset.asset.uniqueId]
        updateDestination(for: selectedAsset)
        startOutboundFeeThresholdRefresh()
        refreshAmountValidators()
        revalidate()
    }

    private func updateDestination(for asset: THORChainAsset) {
        let l1ChainCode = THORChainHelper.securedAssetChain(coinMeta: asset.asset)
        // A `SECURE-` payout always leaves THORChain, so a prefix resolving back
        // to THORChain itself is a malformed denom — `isSecuredDenom` only
        // checks the dash shape, and `securedAssetChain` falls back to "THOR"
        // when it cannot split one. Rejecting it here is what stops such a
        // balance being handed a THORChain address validator and a THORChain
        // address pre-fill, which would look entirely valid.
        let l1Chain = l1ChainCode.caseInsensitiveCompare(Chain.thorChain.swapAsset) == .orderedSame
            ? nil
            : Chain.supportedCases.first { $0.swapAsset.caseInsensitiveCompare(l1ChainCode) == .orderedSame }
        destinationChain = l1Chain

        guard let l1Chain else {
            // The denom names an L1 this app has no chain for, so there is no
            // validator that could tell a payable address from an
            // unrecoverable one. Closed, but never silent.
            let message = missingDestinationMessage(for: asset, chainCode: l1ChainCode, chainName: l1ChainCode)
            destinationField.validators = [
                ClosureValidator { _ in throw HelperError.runtimeError(message) }
            ]
            destinationField.value = .empty
            destinationNotice = message
            return
        }

        destinationField.validators = [
            RequiredValidator(errorMessage: "emptyAddressField".localized),
            AddressValidator(chain: l1Chain)
        ]

        if let l1Coin = vault.nativeCoin(for: l1Chain) {
            destinationField.value = l1Coin.address
            destinationNotice = nil
        } else {
            destinationField.value = .empty
            destinationNotice = missingDestinationMessage(
                for: asset,
                chainCode: l1ChainCode,
                chainName: l1Chain.name
            )
        }
    }

    private func missingDestinationMessage(
        for asset: THORChainAsset,
        chainCode: String,
        chainName: String
    ) -> String {
        String(
            format: "withdrawSecuredAssetError".localized,
            asset.asset.ticker.uppercased(),
            chainCode,
            chainName
        )
    }

    // MARK: - Outbound-fee threshold

    /// Invalidates whatever the threshold currently says and asks again for the
    /// selected asset, under a generation stamp.
    ///
    /// The stamp is the fix for a latest-wins race: the legacy form fired one
    /// unowned task per selection and wrote every reply unconditionally, so a
    /// slow answer for an asset the user had already moved off would overwrite
    /// the current one. The floor then belonged to a different asset — and it
    /// is the only thing standing between a redemption and being swallowed
    /// whole by the outbound fee. Cancelling stops the work; the stamp is what
    /// makes a reply that already escaped cancellation unable to land.
    ///
    /// Every caller that invalidates the selection routes through here, so the
    /// generation is bumped on asset *load* transitions too, not only on
    /// selection — a picker reload while a request is outstanding cannot leave
    /// an obsolete answer able to publish.
    private func startOutboundFeeThresholdRefresh() {
        thresholdGeneration &+= 1
        let generation = thresholdGeneration
        thresholdTask?.cancel()
        thresholdTask = nil

        guard
            let l1Chain = destinationChain,
            let l1Native = vault.nativeCoin(for: l1Chain),
            let assetCoin = selectedAssetCoin
        else {
            outboundFeeThreshold = .notApplicable
            return
        }

        outboundFeeThreshold = .pending
        let inboundChainName = ThorchainService.getInboundChainName(for: l1Chain)

        // `self` is captured weakly and touched only *after* the await, so the
        // view-model can deallocate — and `deinit` can cancel — while the
        // request is in flight. A `guard let self` before the suspension would
        // pin it alive and make that cancellation unreachable.
        thresholdTask = Task { [weak self, dataSource] in
            let fee = await dataSource.outboundFee(forInboundChain: inboundChainName)
            guard let self, generation == self.thresholdGeneration else { return }

            guard let fee else { return self.apply(threshold: .unavailable) }

            let feeFiat = dataSource.fiatValue(of: fee, coin: l1Native)
            let unitFiat = dataSource.fiatValue(of: 1, coin: assetCoin)
            // Fails OPEN on purpose. With no usable price on either side there
            // is no threshold to state, and refusing the redemption would mean
            // a missing rate locks a user out of their own position. The
            // network still rejects a dust payout; a wrong local floor would
            // block a good one.
            guard feeFiat > 0, unitFiat > 0 else { return self.apply(threshold: .unavailable) }

            self.apply(threshold: .known((feeFiat * Self.outboundFeeBuffer) / unitFiat))
        }
    }

    private func apply(threshold: OutboundFeeThreshold) {
        guard outboundFeeThreshold != threshold else { return }
        outboundFeeThreshold = threshold
        refreshAmountValidators()
        revalidate()
    }

    // MARK: - Validation

    private func refreshAmountValidators() {
        guard let assetCoin = selectedAssetCoin else {
            amountField.validators = [Self.noAssetSelectedValidator]
            return
        }

        var validators: [FormFieldValidator] = [
            RequiredValidator(errorMessage: "enterValidAmount".localized),
            AmountBalanceValidator(balance: assetCoin.balanceDecimal)
        ]

        switch outboundFeeThreshold {
        case .pending:
            // Holds the gate shut until the node answers. The floor may land
            // above what the user has already typed, and there is no second
            // check at sign time — leaving the form open here would let a
            // fast Continue walk straight past the guard. It says "please
            // wait" rather than nothing, because a redemption that refuses
            // silently is the failure this operation cannot have.
            validators.append(
                ClosureValidator { _ in
                    throw HelperError.runtimeError("pleaseWait".localized)
                }
            )
        case .known(let minimum):
            validators.append(
                MinAmountValidator(
                    minimum: minimum,
                    errorMessage: String(
                        format: "withdrawBelowOutboundFee".localized,
                        minimum.formatForDisplay(),
                        assetCoin.ticker.uppercased()
                    )
                )
            )
        case .notApplicable, .unavailable:
            // No floor to apply. Deliberately open — see `apply(threshold:)`.
            break
        }

        amountField.validators = validators
    }

    /// Re-runs the fields and republishes the aggregate without waiting for a
    /// value edit. Needed because both this form's rules arrive from outside
    /// the `$value` pipeline the shared `Form` listens on: the address
    /// validator changes with the picker, and the fee floor lands from a
    /// network reply. Errors are not forced — a pristine field stays quiet.
    private func revalidate() {
        for field in form {
            try? field.validateErrors()
        }
        validForm = form.allSatisfy { $0.valid }
    }

    var transactionBuilder: TransactionBuilder? {
        // `validateErrors()` re-runs every field's validators synchronously and
        // writes the answer onto the fields, so the fields — not the published
        // `validForm` — are what this submission is judged on. The aggregate is
        // republished a run-loop turn after an edit, and the fee-floor
        // validator is installed by a network reply the aggregate never
        // observes at all, so reading it here could pass an amount the floor
        // rejects.
        validateErrors()
        guard let assetCoin = selectedAssetCoin else { return nil }
        guard form.allSatisfy({ $0.valid }) else { return nil }

        return SecuredWithdrawTransactionBuilder(
            coin: assetCoin,
            destinationAddress: destinationField.value,
            withdrawAmount: amountField.value.toDecimal()
        )
    }
}
