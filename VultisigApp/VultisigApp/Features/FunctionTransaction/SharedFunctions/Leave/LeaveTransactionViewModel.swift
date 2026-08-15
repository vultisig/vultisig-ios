//
//  LeaveTransactionViewModel.swift
//  VultisigApp
//
//  Node LEAVE form view-model, shared by THORChain and MayaChain. A single
//  field — the node address — validated against the active coin's own chain,
//  so a Maya node address cannot be submitted in a THORChain LEAVE memo.
//

import Combine
import Foundation

@MainActor
final class LeaveTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    /// Pre-fills the field when the caller already knows the node — today the
    /// legacy screen carrying a node address across a function change,
    /// tomorrow a bond position card. Mirrors `BondTransactionViewModel`'s
    /// `initialBondAddress`.
    let initialNodeAddress: String?

    @Published var validForm: Bool = false
    @Published var addressViewModel: AddressViewModel

    private(set) lazy var form: [FormField] = [addressViewModel.field]

    var formCancellable: AnyCancellable?

    init(coin: Coin, vault: Vault, initialNodeAddress: String?) {
        self.coin = coin
        self.vault = vault
        self.initialNodeAddress = initialNodeAddress
        self.addressViewModel = AddressViewModel(
            label: "nodeAddress".localized,
            coin: coin,
            // `AddressValidator` passes an empty string so a pristine field
            // shows no error; the required check is what closes the gate.
            additionalValidators: [RequiredValidator(errorMessage: "emptyAddressField".localized)]
        )
    }

    func onLoad() {
        setupForm()

        if let initialNodeAddress, initialNodeAddress.isNotEmpty {
            addressViewModel.field.value = initialNodeAddress
        }
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }

        return LeaveTransactionBuilder(
            coin: coin,
            nodeAddress: addressViewModel.field.value
        )
    }
}
