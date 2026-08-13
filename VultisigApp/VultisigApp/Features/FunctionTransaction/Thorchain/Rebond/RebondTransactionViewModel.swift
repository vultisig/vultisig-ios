//
//  RebondTransactionViewModel.swift
//  VultisigApp
//
//  THORChain node REBOND form view-model: the validator currently holding the
//  bond, the validator it moves to, and an optional partial amount. The
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
    /// Pre-fills the validator that currently holds the bond when the caller
    /// already knows it — a bond position card tomorrow. Mirrors
    /// `LeaveTransactionViewModel.initialNodeAddress`.
    let initialNodeAddress: String?

    @Published var validForm: Bool = false
    @Published var currentNodeViewModel: AddressViewModel
    @Published var newNodeViewModel: AddressViewModel
    @Published var amountField: FormField

    private(set) lazy var form: [FormField] = [
        currentNodeViewModel.field,
        newNodeViewModel.field,
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

        self.currentNodeViewModel = AddressViewModel(
            label: "nodeAddress".localized,
            coin: coin,
            additionalValidators: [
                runeAssetValidator,
                RequiredValidator(errorMessage: "emptyAddressField".localized)
            ]
        )
        self.newNodeViewModel = AddressViewModel(
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
            currentNodeViewModel.field.value = initialNodeAddress
        }
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        // `validForm` is republished a run-loop turn late — the shared `Form`
        // pipeline hops through `RunLoop.main` — so it can still answer "valid"
        // for an edit made in this same turn. `validateErrors()` just refreshed
        // every field synchronously, so read those too: an amount edited to `0`
        // and submitted before the aggregate settles would otherwise build the
        // whole-bond memo. Both conditions, never one: this only ever tightens
        // the gate, and it becomes redundant once the shared stack recomputes
        // the aggregate synchronously.
        guard validForm, form.allSatisfy({ $0.valid }) else { return nil }

        return RebondTransactionBuilder(
            coin: coin,
            currentNodeAddress: currentNodeViewModel.field.value,
            newNodeAddress: newNodeViewModel.field.value,
            rebondAmount: amountField.value.toDecimal()
        )
    }
}
