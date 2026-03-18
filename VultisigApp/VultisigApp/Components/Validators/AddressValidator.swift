//
//  AddressValidator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

struct AddressValidator: FormFieldValidator {
    let chain: Chain

    func validate(value: String) throws {
        guard value.isNotEmpty else { return }
        guard AddressService.validateAddress(address: value, chain: chain) else {
            throw HelperError.runtimeError("validAddressError".localized)
        }
    }
}
