//
//  AddressTextField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI

/// How an address field and its paste / scan / address book row are drawn.
enum AddressFieldStyle {
    /// Outlined field over a row whose outer bottom corners round off.
    case standard
    /// Caption label, filled field and evenly rounded filled buttons, for use inside a card.
    case card
}

struct AddressTextField: View {
    @Binding var address: String
    let label: String
    let coin: Coin
    @Binding var error: String?
    var errorStyle: CommonTextFieldErrorStyle = .error
    var style: AddressFieldStyle = .standard
    var onAddressResult: (AddressResult?) -> Void

    var body: some View {
        VStack(spacing: 16) {
            CommonTextField(
                text: $address,
                label: label,
                placeholder: "enterAddressHere".localized,
                error: $error,
                isScrollable: true,
                labelStyle: style == .card ? .caption : .secondary,
                errorStyle: errorStyle,
                background: style == .card ? Theme.colors.bgSurface12 : Theme.colors.bgSurface1
            )
            .submitLabel(.next)
            .disableAutocorrection(true)
            .maxLength($address)

            AddressFieldAccessoryStack(
                coin: coin,
                style: style,
                onResult: onAddressResult
            )
        }
    }
}
