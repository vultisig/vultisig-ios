//
//  AddressTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI

struct AddressTextField: View {
    @Binding var address: String
    let label: String
    let coin: Coin
    @Binding var error: String?
    var onAddressResult: (AddressResult?) -> Void

    var body: some View {
        VStack(spacing: 16) {
            CommonTextField(
                text: $address,
                label: label,
                placeholder: "enterAddressHere".localized,
                error: $error,
                isScrollable: true,
                labelStyle: .secondary
            )
            .submitLabel(.next)
            .disableAutocorrection(true)
            .maxLength($address)

            AddressFieldAccessoryStack(
                coin: coin,
                onResult: onAddressResult
            )
        }
    }
}
