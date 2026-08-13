//
//  IBCTransferTransactionViewModel.swift
//  VultisigApp
//
//  Pick a destination chain, an address on it, an amount and an optional memo.
//
//  Three things here are deliberate departures from the sub-model this replaces:
//
//  • The amount field starts **empty**. The legacy form seeded it with the whole
//    balance, which put "send everything and then be unable to pay the fee" one
//    tap away. The ceiling the percentage buttons scale is the balance minus a
//    fee reserve, so even "100%" leaves the fee behind.
//  • The destination address is validated against the **destination** chain, and
//    only once a route is chosen. Legacy fell back to a permissive
//    THOR/Maya/TON check whenever nothing was selected.
//  • The amount is read by `IBCTransferAmount`, which refuses an ambiguous
//    string rather than letting `NumberFormatter` reinterpret it.
//

import Combine
import Foundation

@MainActor
final class IBCTransferTransactionViewModel: ObservableObject, Form {
    /// The asset being transferred, on the source chain.
    let coin: Coin
    let vault: Vault

    @Published var validForm: Bool = false
    @Published private(set) var destinations: [IBCDestination] = []
    @Published private(set) var selectedDestination: IBCDestination?
    @Published var percentageSelected: Double?

    @Published var addressViewModel: AddressViewModel
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "enterAmount".localized
    )
    @Published var memoField = FormField(
        label: "memoLabel".localized,
        placeholder: "memoLabel".localized
    )

    /// Stable for the life of the form. The address field's *validators* are
    /// swapped when the destination changes, rather than the field itself being
    /// replaced — `form` is captured once by `setupForm()`, so a replaced field
    /// would leave the aggregate subscribed to an object nothing writes to.
    private(set) lazy var form: [FormField] = [
        addressViewModel.field,
        amountField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    /// Locale the amount is read in. Injected so a test can pin the separators
    /// instead of inheriting the machine's — which locale is in force is part of
    /// the behaviour under test, since the parse refuses another locale's
    /// convention rather than reinterpreting it.
    private let locale: Locale

    init(coin: Coin, vault: Vault, destinationChain: Chain? = nil, locale: Locale = .current) {
        self.coin = coin
        self.vault = vault
        self.locale = locale
        self.initialDestinationChain = destinationChain
        self.addressViewModel = AddressViewModel(
            label: "destinationAddress".localized,
            coin: coin
        )
    }

    private let initialDestinationChain: Chain?

    func onLoad() {
        // Installed before `setupForm()`: the shared pipeline validates on each
        // field's first emission, so a validator added afterwards would let a
        // pristine form publish `valid`.
        amountField.validators = [
            RequiredValidator(errorMessage: "emptyAmountField".localized),
            IBCTransferAmountValidator(
                balance: spendableBalance,
                decimals: coin.decimals,
                locale: locale
            )
        ]
        applyAddressValidators()
        setupForm()
        normalizePresetAmounts()

        destinations = IBCDestinationCatalog.destinations(for: coin)

        if let initial = destinations.first(where: { $0.chain == initialDestinationChain }) {
            select(initial)
        }
    }

    /// True when this asset has no IBC route at all — an unconnected chain, or
    /// Kujira LVN, which the legacy form also refused to transfer. Drives the
    /// notice and the hard-disabled Continue: no field edit can satisfy it,
    /// which is exactly what `FormScreen.isContinueDisabled` is for.
    var hasNoDestinations: Bool { destinations.isEmpty }

    /// The ceiling the amount validator and the percentage buttons share.
    ///
    /// The IBC fee is paid in the source chain's native denom, so a transfer of
    /// the native asset competes with its own fee — reserve it. A non-native
    /// asset (an `ibc/…` or `factory/…` token) does not: its fee comes out of a
    /// different balance entirely.
    var spendableBalance: Decimal {
        guard coin.isNativeToken else { return coin.balanceDecimal }
        let remaining = coin.balanceDecimal - feeReserve
        return remaining > 0 ? remaining : 0
    }

    /// The chain's fallback fee in human-decimal units. Only an estimate — the
    /// real gas is fetched at verify — but reserving an estimate is what keeps
    /// "max" from consuming the fee it is about to need.
    var feeReserve: Decimal {
        let raw = Decimal(string: coin.feeDefault) ?? .zero
        return raw / pow(Decimal(10), coin.decimals)
    }

    /// Whether the fee can be paid at all.
    ///
    /// For a native transfer the fee competes with the amount, so a liquid
    /// balance under the fee makes `spendableBalance` zero and the amount
    /// validator would reject every input with a misleading "amount exceeded".
    ///
    /// For a non-native asset the fee is drawn from the chain's native coin, and
    /// this checks *that* balance rather than assuming it is fine. Verify's own
    /// fee pre-flight skips the check entirely when the vault holds no native
    /// coin for the chain, so a token transfer from a vault with no gas would
    /// otherwise reach the signing ceremony before failing.
    var hasSufficientBalanceForFee: Bool {
        guard !coin.isNativeToken else { return coin.balanceDecimal > feeReserve }
        guard let feeCoin = vault.coins.first(where: { $0.chain == coin.chain && $0.isNativeToken }) else {
            return false
        }
        return feeCoin.balanceDecimal >= nativeFeeReserve(for: feeCoin)
    }

    private func nativeFeeReserve(for feeCoin: Coin) -> Decimal {
        let raw = Decimal(string: feeCoin.feeDefault) ?? .zero
        return raw / pow(Decimal(10), feeCoin.decimals)
    }

    /// The two pre-flight conditions no field edit can satisfy — the case
    /// `FormScreen.isContinueDisabled` exists for. Everything else leaves
    /// Continue tappable, because the tap is what reveals the field errors.
    var isContinueDisabled: Bool {
        hasNoDestinations || !hasSufficientBalanceForFee
    }

    func select(_ destination: IBCDestination) {
        guard destination != selectedDestination else { return }
        selectedDestination = destination

        // The address that was valid for the previous chain almost certainly is
        // not valid for this one, and leaving it in place with a stale "valid"
        // is how a transfer goes to an address on the wrong chain.
        applyAddressValidators()
        addressViewModel.field.value = prefilledAddress(for: destination) ?? .empty
        try? addressViewModel.field.validateErrors()
        validForm = form.allSatisfy { $0.valid }
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()

        // The fields, not the published aggregate: `validForm` is republished a
        // run-loop turn after a field changes, so reading it here rejects a form
        // the user has just completed and accepts one they have just broken.
        guard form.allSatisfy({ $0.valid }) else { return nil }

        guard let destination = selectedDestination,
              hasSufficientBalanceForFee,
              let amount = IBCTransferAmount.parse(
                  amountField.rawValue,
                  decimals: coin.decimals,
                  locale: locale
              ),
              amount > 0,
              amount <= spendableBalance else {
            return nil
        }

        return IBCTransferTransactionBuilder(
            coin: coin,
            destination: destination,
            destinationAddress: addressViewModel.field.value,
            userMemo: memoField.value,
            // Rendered at the coin's scale by the same call the legacy
            // sub-model made, so the base-unit amount downstream is unchanged
            // for any value the legacy form could produce. The shared
            // `SendCryptoLogic.amountInRaw` reads it back through
            // `NumberFormatter`, which is `Double`-backed past ~15 significant
            // digits — a pre-existing property of that path, not of this parse,
            // and deviating from the legacy rendering here would trade a
            // theoretical rounding for a real difference in signed bytes.
            amount: amount.formatToDecimal(digits: coin.decimals)
        )
    }

    // MARK: - Amount

    /// Re-renders a percentage preset's value without grouping separators.
    ///
    /// The shared amount field computes a preset as
    /// `Decimal.formatToDecimal(digits:)`, which groups — so a 25% of 4000 lands
    /// in the field as `1,000`, and that is precisely the spelling `parse`
    /// refuses, because from text alone it cannot be told from another locale's
    /// `1.000`. The refusal is right for text a user pasted and wrong for text
    /// the app computed, and the percentage is what tells the two apart: the
    /// field clears it the moment the user types.
    ///
    /// Deferred a run-loop turn so it lands *after* the field's own write, which
    /// happens during the SwiftUI update that the same publisher triggers.
    private func normalizePresetAmounts() {
        $percentageSelected
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] percentage in
                guard let self else { return }
                let amount = self.spendableBalance * Decimal(percentage) / 100
                let plain = IBCTransferAmount.plainSpelling(
                    of: amount,
                    decimals: self.coin.decimals,
                    locale: self.locale
                )
                guard self.amountField.value != plain else { return }
                self.amountField.value = plain
            }
            .store(in: &cancellables)
    }

    // MARK: - Address

    /// Validators for the *destination* chain, not the source. A `kujira1…`
    /// address in a transfer to Gaia names an account that chain has never
    /// heard of; the funds land in the void on arrival.
    private func applyAddressValidators() {
        var validators: [FormFieldValidator] = [
            RequiredValidator(errorMessage: "emptyAddressField".localized)
        ]
        if let chain = selectedDestination?.chain {
            validators.insert(AddressValidator(chain: chain), at: 0)
        }
        addressViewModel.field.validators = validators
    }

    /// The user's own address on the destination chain, when the vault holds
    /// that coin — the common case for an IBC transfer and what the legacy form
    /// pre-filled. Editable: the field is a plain address field.
    private func prefilledAddress(for destination: IBCDestination) -> String? {
        vault.coins.first { $0.chain == destination.chain && $0.isNativeToken }?.address
    }
}
