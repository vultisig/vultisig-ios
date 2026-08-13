//
//  MergeTransactionViewModel.swift
//  VultisigApp
//
//  Rujira MERGE form view-model. Two decisions: which mergeable token, and how
//  much of it. The token carries the destination contract and the balance the
//  amount is bounded by, so both move together on every selection.
//

import Combine
import Foundation

@MainActor
final class MergeTransactionViewModel: ObservableObject, Form {
    /// THORChain's native asset — the chain anchor and the fee asset. It is
    /// deliberately *not* the coin the transaction is built against: MERGE
    /// deposits whichever catalog token the user picks below, and the picker
    /// only offers coins the vault already holds.
    let coin: Coin
    let vault: Vault
    /// Catalog denom to open on, when the caller already knows which token the
    /// user means. Matched case-insensitively and ignored when the vault does
    /// not hold it.
    let initialDenom: String?

    /// The catalog intersected with the vault's holdings, in catalog order.
    let mergeableAssets: [ThorchainMergeAsset]

    @Published var validForm: Bool = false
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0"
    )
    @Published private(set) var selectedAsset: ThorchainMergeAsset?

    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?

    var assetsDataSource: AssetSelectionDataSource {
        ThorchainMergeAssetsDataSource(assets: mergeableAssets.map { $0.pickerAsset })
    }

    /// The legacy form labelled the amount with the selected token's balance,
    /// and said "select a token" until one was picked. Same two strings.
    var amountLabel: String {
        guard let selectedAsset else { return "amountSelectToken".localized }

        return String(
            format: "amountBalance".localized,
            selectedAsset.coin.balanceDecimal.formatForDisplay(),
            selectedAsset.coin.ticker.uppercased()
        )
    }

    init(coin: Coin, vault: Vault, initialDenom: String?) {
        self.coin = coin
        self.vault = vault
        self.initialDenom = initialDenom
        self.mergeableAssets = ThorchainMergeAsset.mergeable(in: vault, chain: coin.chain)
        self.amountField.validators = Self.validators(for: nil)
    }

    func onLoad() {
        setupForm()

        guard
            let initialDenom,
            let preselected = mergeableAssets.first(where: {
                $0.token.denom.caseInsensitiveCompare(initialDenom) == .orderedSame
            })
        else { return }

        select(asset: preselected)
    }

    /// Picker callback. Resolving the descriptor here rather than in the view
    /// is what keeps the contract address out of the screen.
    func select(pickerAsset: THORChainAsset?) {
        guard let match = mergeableAssets.first(where: { $0.pickerAsset == pickerAsset }) else { return }
        select(asset: match)
    }

    func select(asset: ThorchainMergeAsset) {
        selectedAsset = asset
        // The balance bound belongs to the token, so it is rebuilt rather than
        // appended — switching tokens must not leave the previous one's
        // ceiling in place.
        amountField.validators = Self.validators(for: asset)
        // Legacy pre-filled the whole balance on selection. Formatted through
        // the same locale-aware path the legacy amount took, so it parses back
        // to the same Decimal downstream.
        amountField.value = asset.coin.balanceDecimal.formatToDecimal(digits: asset.coin.decimals)
        refreshValidity()
    }

    var transactionBuilder: TransactionBuilder? {
        // `AmountBalanceValidator`'s ceiling is a copy taken when the token was
        // picked, while the legacy gate compared against the balance read at
        // submit. Rebuilding the validators here restores that in both
        // directions: a balance that dropped no longer passes, and one that
        // grew no longer rejects an amount the user can now afford.
        amountField.validators = Self.validators(for: selectedAsset)
        validateErrors()

        // Read the flags `validateErrors()` has just written rather than the
        // published `validForm`: that aggregate lands a run-loop turn late, so
        // a form invalidated in this turn would still answer "valid" to a tap.
        guard form.allSatisfy({ $0.valid }), let selectedAsset else { return nil }

        // Legacy also required a non-empty destination. It costs one guard to
        // keep, and an empty `toAddress` on a `.thorMerge` is a deposit signed
        // to nowhere.
        guard !selectedAsset.contractAddress.isEmpty else { return nil }

        return MergeTransactionBuilder(
            coin: selectedAsset.coin,
            denom: selectedAsset.memoDenom,
            contractAddress: selectedAsset.contractAddress,
            amount: amountField.value
        )
    }
}

private extension MergeTransactionViewModel {
    static func validators(for asset: ThorchainMergeAsset?) -> [FormFieldValidator] {
        guard let asset else {
            // No token picked yet: the gate stays closed, and Continue's
            // `validateErrors()` has to say why rather than silently no-op.
            return [ClosureValidator { _ in
                throw HelperError.runtimeError("selectTokenToMerge".localized)
            }]
        }

        return [
            RequiredValidator(errorMessage: "emptyAmountField".localized),
            // Carries the legacy submit-time gate: amount > 0 and within the
            // selected token's balance.
            AmountBalanceValidator(balance: asset.coin.balanceDecimal)
        ]
    }

    /// `setupForm()` only re-evaluates when a field's *value* changes, and
    /// selecting a token changes its *validators*. Re-run the same predicate
    /// so the gate can never hold a verdict that belonged to another token.
    func refreshValidity() {
        validForm = form.allSatisfy { field in
            do {
                try field.validateErrors()
                return true
            } catch {
                return false
            }
        }
    }
}
