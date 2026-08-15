//
//  RebondTransactionViewModel.swift
//  VultisigApp
//
//  THORChain node REBOND form view-model: the node holding the bond, the
//  address the protocol rebonds to, and an optional partial amount. The
//  "REBOND requires RUNE" rule is a form validator here rather than a label —
//  the legacy sub-model wrote that message to a slot its validity gate never
//  read, so an unsupported asset only looked blocked.
//

import Combine
import Foundation

@MainActor
final class RebondTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    /// Pre-fills the node holding the bond when the caller already knows it —
    /// a bond position card tomorrow. Mirrors
    /// `LeaveTransactionViewModel.initialNodeAddress`.
    let initialNodeAddress: String?

    @Published var validForm: Bool = false
    @Published var nodeViewModel: AddressViewModel
    @Published var newAddressViewModel: AddressViewModel
    @Published var amountField: FormField

    private(set) lazy var form: [FormField] = [
        nodeViewModel.field,
        newAddressViewModel.field,
        amountField
    ]

    var formCancellable: AnyCancellable?

    init(coin: Coin, vault: Vault, initialNodeAddress: String?) {
        self.coin = coin
        self.vault = vault
        self.initialNodeAddress = initialNodeAddress

        // Captured as a value rather than through `self` so the validator
        // holds no reference back to the view-model. It ignores the field
        // content on purpose: no address the user can type makes a non-RUNE
        // asset a legal REBOND, so the gate has to close on the asset alone.
        let carriesRune = coin.chain == .thorChain && coin.isNativeToken
        let runeAssetValidator = ClosureValidator { _ in
            guard carriesRune else {
                throw HelperError.runtimeError("rebondRequiresRune".localized)
            }
        }

        self.nodeViewModel = AddressViewModel(
            label: "nodeAddress".localized,
            coin: coin,
            additionalValidators: [
                runeAssetValidator,
                RequiredValidator(errorMessage: "emptyAddressField".localized)
            ]
        )
        self.newAddressViewModel = AddressViewModel(
            label: "newAddress".localized,
            coin: coin,
            additionalValidators: [RequiredValidator(errorMessage: "emptyAddressField".localized)]
        )
        self.amountField = FormField(
            label: "amount".localized,
            placeholder: "rebondAmountPlaceholder".localized,
            validators: [
                ClosureValidator { value in
                    // Empty is the whole-bond shape, so an untouched field is
                    // valid. A typed amount has to survive the memo's 1e8
                    // truncation: `0`, junk and sub-base-unit dust all scale to
                    // zero, which would put a `:0` segment on the memo and
                    // rebond nothing. Legacy accepted all three.
                    guard value.isNotEmpty else { return }
                    guard RebondTransactionBuilder.memoUnits(from: value.toDecimal()) > 0 else {
                        throw HelperError.runtimeError("invalidAmount".localized)
                    }
                }
            ]
        )
    }

    func onLoad() {
        setupForm()

        if let initialNodeAddress, initialNodeAddress.isNotEmpty {
            nodeViewModel.field.value = initialNodeAddress
        }
    }

    var transactionBuilder: TransactionBuilder? {
        // `validateErrors()` re-runs every field's validators synchronously and
        // writes the answer to `field.valid`, so the fields — not the published
        // `validForm` — are what this turn's submission is judged on. The
        // aggregate is republished a run-loop turn late (the shared `Form`
        // pipeline hops through `RunLoop.main`), and reading it here would be
        // wrong in both directions: an amount edited to `0` and submitted
        // before it settles would build the whole-bond memo, and a form that
        // just became valid would refuse the first tap. Once the shared stack
        // recomputes the aggregate synchronously the two are the same read.
        validateErrors()
        guard form.allSatisfy({ $0.valid }) else { return nil }

        return RebondTransactionBuilder(
            coin: coin,
            nodeAddress: nodeViewModel.field.value,
            newAddress: newAddressViewModel.field.value,
            rebondAmount: amountField.value.toDecimal()
        )
    }
}
