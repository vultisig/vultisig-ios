//
//  FunctionAddressField.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 04/11/2025.
//

import SwiftUI

struct FunctionAddressField: View {
    @StateObject var viewModel: AddressViewModel

    var body: some View {
        AddressTextField(
            address: $viewModel.field.value,
            label: viewModel.field.label ?? .empty,
            coin: viewModel.coin,
            error: $viewModel.field.error
        ) {
            viewModel.handle(addressResult: $0)
        }
    }
}
