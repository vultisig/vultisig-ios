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
    /// Smallest redemption that still clears THORChain's L1 outbound fee, in
    /// units of the selected secured asset. Zero means "not known" — see
    /// `startOutboundFeeThresholdRefresh`.
    @Published private(set) var minimumWithdrawAmount: Decimal = 0
    /// Explains a destination the vault cannot pre-fill. Deliberately not an
    /// error on the field: the user can still paste an address they control,
    /// and this is the only route out of a secured position.
    @Published private(set) var destinationNotice: String?

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
    func displayName(for asset: THORChainAsset) -> String {
        "\(THORChainHelper.securedAssetChain(coinMeta: asset.asset)).\(asset.asset.ticker.uppercased())"
    }

    var selectedAssetDisplayName: String {
        guard let selectedAsset else { return "selectSecuredAssetToWithdraw".localized }
        return displayName(for: selectedAsset)
    }

    var balanceDescription: String {
        guard let selectedAsset, let assetCoin = selectedAssetCoin else {
            return "selectSecuredAssetToSeeBalance".localized
        }
        return String(
            format: "balanceInParentheses".localized,
            assetCoin.balanceDecimal.formatForDisplay(),
            displayName(for: selectedAsset)
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

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let assets = try await self.fetchSecuredAssets()
                guard !Task.isCancelled else { return }
                self.apply(securedAssets: assets)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to fetch THORChain balances: \(error.localizedDescription, privacy: .public)")
                self.applyEmptyPicker(reason: "noSecuredAssets".localized)
            }
        }
    }

    private func fetchSecuredAssets() async throws -> [(asset: THORChainAsset, coin: Coin)] {
        let balances = try await dataSource.securedAssetBalances(address: coin.address, chain: coin.chain)

        var held: [(asset: THORChainAsset, coin: Coin)] = []
        for balance in balances where Self.isSecuredDenom(balance.denom) {
            let meta = SecuredAssetMapper.coinMeta(forDenom: balance.denom, chain: coin.chain)
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

        return held.sorted { displayName(for: $0.asset) < displayName(for: $1.asset) }
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
    }

    private func applyEmptyPicker(reason: String) {
        availableAssets = []
        securedAssetCoins = [:]
        selectedAsset = nil
        selectedAssetCoin = nil
        loadError = reason
        isLoadingAssets = false
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
        let l1Chain = Chain.allCases.first { $0.swapAsset.caseInsensitiveCompare(l1ChainCode) == .orderedSame }
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

    /// Clears the threshold and asks for the selected asset's, under a
    /// generation stamp.
    ///
    /// The stamp is the fix for a latest-wins race: the legacy form fired one
    /// unowned task per selection and wrote every reply unconditionally, so a
    /// slow answer for an asset the user had already moved off would overwrite
    /// the current one. `minimumWithdrawAmount` then belonged to a different
    /// asset — and it is the only thing standing between a redemption and
    /// being swallowed whole by the outbound fee. Cancelling stops the work;
    /// the stamp is what makes a reply that already escaped cancellation
    /// unable to land.
    private func startOutboundFeeThresholdRefresh() {
        thresholdGeneration &+= 1
        let generation = thresholdGeneration
        thresholdTask?.cancel()
        thresholdTask = nil
        minimumWithdrawAmount = 0

        guard
            let l1Chain = destinationChain,
            let l1Native = vault.nativeCoin(for: l1Chain),
            let assetCoin = selectedAssetCoin
        else {
            return
        }

        let inboundChainName = ThorchainService.getInboundChainName(for: l1Chain)

        thresholdTask = Task { [weak self] in
            guard let self else { return }
            let fee = await self.dataSource.outboundFee(forInboundChain: inboundChainName)
            guard generation == self.thresholdGeneration else { return }
            guard let fee else { return }

            let feeFiat = self.dataSource.fiatValue(of: fee, coin: l1Native)
            let unitFiat = self.dataSource.fiatValue(of: 1, coin: assetCoin)
            // Fails OPEN on purpose. With no usable price on either side there
            // is no threshold to state, and refusing the redemption would mean
            // a missing rate locks a user out of their own position. The
            // network still rejects a dust payout; a wrong local floor would
            // block a good one.
            guard feeFiat > 0, unitFiat > 0 else { return }

            self.apply(minimumWithdrawAmount: (feeFiat * Self.outboundFeeBuffer) / unitFiat)
        }
    }

    private func apply(minimumWithdrawAmount: Decimal) {
        guard self.minimumWithdrawAmount != minimumWithdrawAmount else { return }
        self.minimumWithdrawAmount = minimumWithdrawAmount
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

        if minimumWithdrawAmount > 0 {
            validators.append(
                MinAmountValidator(
                    minimum: minimumWithdrawAmount,
                    errorMessage: String(
                        format: "withdrawBelowOutboundFee".localized,
                        minimumWithdrawAmount.formatForDisplay(),
                        assetCoin.ticker.uppercased()
                    )
                )
            )
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
