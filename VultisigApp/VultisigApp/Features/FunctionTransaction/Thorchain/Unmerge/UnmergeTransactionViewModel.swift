//
//  UnmergeTransactionViewModel.swift
//  VultisigApp
//
//  THORChain RUJI UNMERGE form view-model: pick a merged token, type a share
//  count, withdraw. Two properties are load-bearing and both were broken in the
//  legacy sub-model:
//
//  • The share count is a raw `BigInt` from the field to the memo. The legacy
//    path went Decimal → Double → `%.0f`, which rounds a large share count into
//    a different withdrawal.
//  • The balance fetch is latest-wins. The legacy one dropped a request while
//    another was in flight and wrote whatever came back unconditionally, so
//    selecting a second token before the first answered left the form validating
//    — and the memo built — against the first token's shares.
//

import BigInt
import Combine
import Foundation

private let logger = Log.send.viewModel

/// The RUJI merge-account read the form depends on. Injected so the
/// latest-wins behaviour can be exercised with a source that answers out of
/// order; production passes `ThorchainService.shared`.
protocol RujiMergeBalanceSource {
    func fetchRujiMergeBalance(thorAddr: String, tokenSymbol: String) async throws -> ThorchainService.RujiBalance
}

extension ThorchainService: RujiMergeBalanceSource {}

@MainActor
final class UnmergeTransactionViewModel: ObservableObject, Form {
    /// The coin the intent resolved — THORChain's native asset. It is the
    /// fallback signing coin and the reason `resolvingCoin` fails closed on a
    /// vault that cannot pay the fee; the merged token itself is resolved per
    /// selection in `signingCoin(for:)`.
    let coin: Coin
    let vault: Vault
    /// Merge denom to open on, when the caller already knows which token the
    /// user came from. Falls back to the first offered token.
    let initialDenom: String?

    @Published var validForm: Bool = false
    @Published private(set) var selectedToken: THORChainAsset?
    @Published private(set) var isLoading: Bool = false
    /// Label for the amount section: the four states the legacy form's balance
    /// label had — loading, loaded, no THORChain address, fetch failed.
    @Published private(set) var sharesLabel: String = "loading".localized
    /// Available shares in 1e8 base units, exactly as the merge account reports
    /// them. Never round-tripped through a `Double`: it is both the display
    /// ceiling and the validation ceiling.
    @Published private(set) var availableShares: BigInt = .zero
    @Published var percentageSelected: Double?
    @Published var amountField = FormField(placeholder: "enterAmountToUnmerge".localized)

    let assetsDataSource = MergeTokenDataSource()

    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?

    private let balanceSource: RujiMergeBalanceSource
    /// Monotonic stamp identifying the newest balance request. Every write a
    /// request makes goes through `apply(shares:generation:)` /
    /// `apply(failureLabel:generation:)` and is gated on it, which is what makes
    /// the read latest-wins rather than last-to-answer-wins: cancellation is
    /// cooperative and cannot stop a response that has already resolved, so the
    /// stamp — not the `cancel()` — is the enforcement.
    private var balanceGeneration: UInt64 = 0
    private var balanceTask: Task<Void, Never>?

    /// Locale the share amount is read in. Injected so a test pins the
    /// separators rather than inheriting the machine's — the parse deliberately
    /// refuses an amount written in another locale's convention, so which locale
    /// is in force is part of the behaviour under test.
    private let locale: Locale

    init(
        coin: Coin,
        vault: Vault,
        initialDenom: String?,
        balanceSource: RujiMergeBalanceSource = ThorchainService.shared,
        locale: Locale = .current
    ) {
        self.coin = coin
        self.vault = vault
        self.initialDenom = initialDenom
        self.balanceSource = balanceSource
        self.locale = locale
    }

    deinit {
        balanceTask?.cancel()
    }

    func onLoad() {
        // Installed before `setupForm()`: the shared pipeline validates on the
        // field's first emission, so a validator added afterwards would let a
        // pristine form publish `valid`.
        amountField.validators = [
            ClosureValidator { [weak self] value in
                guard let self else { return }
                guard let shares = UnmergeShares.parse(value, locale: self.locale), shares > 0 else {
                    throw HelperError.runtimeError("enterValidAmount".localized)
                }
                guard shares <= self.availableShares else {
                    throw HelperError.runtimeError("insufficientBalanceForFunctions".localized)
                }
            }
        ]
        setupForm()

        let initial = MergeTokenCatalog.tokens.first {
            $0.thorchainAsset.caseInsensitiveCompare(initialDenom ?? .empty) == .orderedSame
        } ?? MergeTokenCatalog.tokens.first

        if let initial {
            select(initial)
        }
    }

    /// Available shares as a human decimal — what the amount field is typed in
    /// and what its percentage buttons scale.
    var availableAmount: Decimal {
        UnmergeShares.decimalValue(of: availableShares)
    }

    /// Re-selecting the same token deliberately refetches, as the legacy form
    /// did — it is the only way back from a failed read.
    func select(_ token: THORChainAsset) {
        selectedToken = token
        // The previous token's shares are meaningless under the new one, and
        // leaving them visible for the length of a fetch is how the legacy form
        // let an amount be typed against the wrong ceiling.
        availableShares = .zero
        amountField.value = .empty
        amountField.error = nil
        // The cleared field is pristine again, so the shared `FormField` error
        // display should not treat it as a field the user abandoned empty.
        amountField.touched = false
        percentageSelected = nil
        sharesLabel = "loading".localized

        balanceGeneration &+= 1
        let generation = balanceGeneration
        balanceTask?.cancel()
        balanceTask = nil

        let thorAddress = vault.coins.first { $0.chain == .thorChain }?.address ?? .empty
        guard thorAddress.isNotEmpty else {
            logger.error("No THORChain address found in vault")
            apply(failureLabel: "noThorAddressFound".localized, generation: generation)
            return
        }

        isLoading = true
        // `self` is captured weakly and touched only after the await, so a
        // screen popped mid-request deallocates immediately and `deinit` gets to
        // cancel — calling an instance method across the await instead would
        // hold the view-model (and its vault) for the length of a hung request.
        balanceTask = Task { [weak self, balanceSource] in
            do {
                let balance = try await balanceSource.fetchRujiMergeBalance(
                    thorAddr: thorAddress,
                    tokenSymbol: token.thorchainAsset
                )
                self?.apply(shares: BigInt(balance.shares) ?? .zero, generation: generation)
            } catch {
                logger.error("Error fetching merged balance: \(error.localizedDescription, privacy: .public)")
                self?.apply(failureLabel: "errorLoadingBalance".localized, generation: generation)
            }
        }
    }

    var transactionBuilder: TransactionBuilder? {
        // The fields, not the published `validForm`, are what this turn's
        // submission is judged on: the aggregate is republished a run-loop turn
        // late, and the balance it depends on arrives asynchronously, so reading
        // it here would be wrong in both directions.
        validateErrors()
        guard form.allSatisfy({ $0.valid }) else { return nil }

        guard let selectedToken,
              let contractAddress = MergeTokenCatalog.contractAddress(for: selectedToken.thorchainAsset),
              let shares = UnmergeShares.parse(amountField.rawValue, locale: locale),
              shares > 0,
              shares <= availableShares else {
            return nil
        }

        return UnmergeTransactionBuilder(
            coin: signingCoin(for: selectedToken),
            denom: selectedToken.thorchainAsset,
            contractAddress: contractAddress,
            shares: shares
        )
    }

    // MARK: - Balance

    /// The only write-back from a balance request, success side. Superseded
    /// generations return without touching anything — a response that has
    /// already resolved cannot be cancelled, so this guard, not the `cancel()`
    /// above, is what makes the read latest-wins.
    private func apply(shares: BigInt, generation: UInt64) {
        guard generation == balanceGeneration else { return }
        availableShares = shares
        sharesLabel = "sharesLabel".localized
        isLoading = false
        refreshValidity()
    }

    /// The same write-back for every way the read can fail — no THORChain
    /// address, or the request itself. Under the same generation guard, so a
    /// stale failure cannot clear the balance the current selection just loaded.
    private func apply(failureLabel: String, generation: UInt64) {
        guard generation == balanceGeneration else { return }
        availableShares = .zero
        sharesLabel = failureLabel
        isLoading = false
        refreshValidity()
    }

    /// Re-runs the amount validator against the balance that just landed and
    /// republishes the aggregate. Deliberately not `validateErrors()`: that
    /// forces errors onto a field the user has not touched yet.
    private func refreshValidity() {
        try? amountField.validateErrors()
        validForm = form.allSatisfy { $0.valid }
    }

    /// The vault's own coin for the selected merge token, falling back to the
    /// chain's native asset. Reproduces the legacy screen's coin binding, which
    /// pointed the transaction at the merged token when the vault held it. The
    /// wasm execute reads only the sender address, the contract and the memo, so
    /// this changes what the verify screen and history show, never what is
    /// signed.
    private func signingCoin(for token: THORChainAsset) -> Coin {
        let ticker = token.thorchainAsset
            .lowercased()
            .replacingOccurrences(of: "thor.", with: "")
        let held = vault.coins.first {
            $0.chain == .thorChain && !$0.isNativeToken && $0.ticker.lowercased() == ticker
        }
        return held ?? coin
    }
}
