//
//  SwapVerifyViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import SwiftUI

@MainActor
class SwapCryptoVerifyViewModel: ObservableObject {

    @Published var isAmountCorrect = false
    @Published var isFeeCorrect = false
    @Published var isApproveCorrect = false

    func isValidForm(shouldApprove: Bool) -> Bool {
        if shouldApprove {
            return isAmountCorrect && isFeeCorrect && isApproveCorrect
        } else {
            return isAmountCorrect && isFeeCorrect
        }
    }
}
