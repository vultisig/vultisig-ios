//
//  SwapCryptoApproveViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 20.05.2024.
//

import SwiftUI

@MainActor
class SwapCryptoApproveViewModel: ObservableObject {

    @Published var isAllowanceCorrect = false

    var isValidForm: Bool {
        return isAllowanceCorrect
    }
}
