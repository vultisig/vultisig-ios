//
//  AddressViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/11/2025.
//

import Foundation

final class AddressViewModel: ObservableObject {
    let coin: Coin
    @Published var field: FormField

    init(label: String? = nil, coin: Coin, additionalValidators: [FormFieldValidator] = []) {
        self.field = FormField(
            label: label ?? "address".localized,
            placeholder: "enterAddress".localized,
            validators: [
                AddressValidator(chain: coin.chain)
            ] + additionalValidators
        )
        self.coin = coin
    }

    func handle(addressResult: AddressResult?) {
        guard let address = addressResult?.address else { return }
        field.value = address
    }
}
