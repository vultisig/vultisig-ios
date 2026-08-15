//
//  CustomMemoTransactionViewModel.swift
//  VultisigApp
//
//  Raw-memo `MsgDeposit` form view-model, shared by THORChain (mainnet plus
//  both test networks) and MayaChain. Three inputs: which of the vault's coins
//  the deposit rides on, an optional amount of it, and the memo.
//
//  The memo is never touched. It is carried to the builder exactly as typed —
//  the form's only say over it is whether to submit at all, and a blank or
//  whitespace-only string is the one answer that is "no". Legacy accepted a
//  memo of pure spaces (`!custom.isEmpty`); that names no operation on either
//  chain and buys a wasted deposit fee, so it is refused here and pinned by a
//  test rather than left as a silent change.
//

import Combine
import Foundation

@MainActor
final class CustomMemoTransactionViewModel: ObservableObject, Form {
    /// The chain the deposit is made on. Scoping the asset list to it is what
    /// stops a picked ticker from resolving to a coin on another chain — the
    /// picked coin *is* the coin the memo is deposited against.
    let chain: Chain
    let vault: Vault
    /// The vault's coins this form can deposit with, resolved once at
    /// construction. Empty is a legitimate state: a vault holding no supported
    /// asset on the chain has nothing to select, and therefore builds nothing.
    let depositableCoins: [Coin]

    @Published var validForm: Bool = false
    /// The picked asset. Its `didSet` — rather than a Combine subscription —
    /// re-checks the amount, because `@Published` publishes in `willSet` and a
    /// subscriber would still read the previous coin's balance.
    @Published var selectedAsset: THORChainAsset? {
        didSet {
            guard oldValue != selectedAsset else { return }
            onAssetChanged()
        }
    }
    // The placeholder is the localisation *key*: `CommonTextField` localises
    // what it is handed, so a pre-localised string would come back English in
    // every other locale.
    @Published var memoField = FormField(label: "customMemo".localized, placeholder: "customMemo")
    @Published var amountField = FormField(label: "amount".localized, placeholder: "0")
    @Published var percentageSelected: Double?

    private(set) lazy var form: [FormField] = [memoField, amountField]

    var formCancellable: AnyCancellable?

    /// Locale the amount is read in. Injected so a test pins the separators
    /// rather than inheriting the machine's — the parse deliberately refuses an
    /// amount written in another locale's convention, so which locale is in
    /// force is part of the behaviour under test.
    private let locale: Locale

    init(coin: Coin, vault: Vault, locale: Locale = .current) {
        self.chain = coin.chain
        self.vault = vault
        self.locale = locale
        self.depositableCoins = CustomMemoAssets.depositableCoins(in: vault, on: coin.chain)
        // Pre-select the coin the user entered from when this form can deposit
        // with it. When it cannot, the picker deliberately opens empty rather
        // than falling back to the chain's native asset: the memo was written
        // for something, and silently attaching it to RUNE is a different
        // transaction from the one the user is composing.
        self.selectedAsset = Self.assets(for: depositableCoins).first { $0.asset == coin.toCoinMeta() }
    }

    /// The picker's rows. A local list, so the sheet resolves instantly and
    /// cannot show an asset the vault does not hold.
    var assetsDataSource: AssetSelectionDataSource {
        LocalAssetSelectionDataSource(assets: Self.assets(for: depositableCoins))
    }

    /// The vault coin the picker currently names, or nil while nothing is
    /// selected. Matched on the full `CoinMeta` rather than on a ticker: the
    /// rows are built from these very coins, so the round-trip is exact.
    var selectedCoin: Coin? {
        guard let asset = selectedAsset?.asset else { return nil }
        return depositableCoins.first { $0.toCoinMeta() == asset }
    }

    func onLoad() {
        // Installed before `setupForm()`: the shared pipeline validates on the
        // field's first emission, so a validator added afterwards would let a
        // pristine form publish `valid`.
        memoField.validators = [
            ClosureValidator { value in
                guard value.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty else {
                    throw HelperError.runtimeError("emptyField".localized)
                }
            }
        ]
        amountField.validators = [
            ClosureValidator { [weak self] value in
                guard let self else { return }
                // Optional by design: a memo-only `MsgDeposit` attaches
                // nothing, which is most of this form's traffic.
                guard value.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty else { return }
                guard let coin = self.selectedCoin else {
                    // Nothing to measure the amount against yet. The asset
                    // picker is what the form is waiting on, not this field.
                    return
                }
                guard let amount = HumanDecimalAmount.parse(
                    value,
                    decimals: coin.decimals,
                    locale: self.locale
                ) else {
                    throw HelperError.runtimeError("invalidAmount".localized)
                }
                guard amount <= coin.balanceDecimal else {
                    throw HelperError.runtimeError("amountExceeded".localized)
                }
            }
        ]
        setupForm()
    }

    /// The amount's ceiling belongs to the selected coin, and the picker moves
    /// it without any field value changing — the shared validation pipeline is
    /// driven by field values and would never re-run on its own.
    private func onAssetChanged() {
        // A percentage of the previous coin's balance is not a percentage of
        // this one's.
        percentageSelected = nil
        try? amountField.validateErrors()
        let isValid = form.allSatisfy { $0.valid }
        if validForm != isValid {
            validForm = isValid
        }
    }

    var transactionBuilder: TransactionBuilder? {
        // `validateErrors()` re-runs every field's validators synchronously and
        // writes the answer to `field.valid`, so the fields — not the published
        // `validForm` — are what this turn's submission is judged on. The
        // aggregate is republished a run-loop turn late, and the asset picker
        // can invalidate the amount without any field value changing.
        validateErrors()
        guard form.allSatisfy({ $0.valid }) else { return nil }

        guard let coin = selectedCoin else { return nil }

        // Re-checked here rather than trusted from the validator: this is the
        // one gate between a blank memo and a signed deposit that does nothing.
        let memo = memoField.value
        guard memo.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty else { return nil }

        guard let amount = parsedAmount(for: coin), amount >= 0, amount <= coin.balanceDecimal else {
            return nil
        }

        return CustomMemoTransactionBuilder(coin: coin, customMemo: memo, customAmount: amount)
    }

    /// The typed amount, or zero when the field is blank. Nil only when a
    /// non-blank amount is not a number in this form's locale.
    private func parsedAmount(for coin: Coin) -> Decimal? {
        let value = amountField.value
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty else { return .zero }
        return HumanDecimalAmount.parse(value, decimals: coin.decimals, locale: locale)
    }

    private static func assets(for coins: [Coin]) -> [THORChainAsset] {
        coins.map {
            THORChainAsset(thorchainAsset: "\($0.chain.ticker).\($0.ticker)", asset: $0.toCoinMeta())
        }
    }
}

/// An `AssetSelectionDataSource` over a list already in memory. The Maya
/// sources fetch from the network; this form's rows are the vault's own coins,
/// so there is nothing to await.
struct LocalAssetSelectionDataSource: AssetSelectionDataSource {
    let assets: [THORChainAsset]

    // Nothing to await — `async` is the protocol's, not this conformer's.
    // swiftlint:disable:next async_without_await
    func fetchAssets() async -> [THORChainAsset] { assets }
}
