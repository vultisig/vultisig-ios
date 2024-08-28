//
//  SendGasSettingsViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 28.08.2024.
//

import Foundation
import BigInt

final class SendGasSettingsViewModel: ObservableObject {

    @Published var gasLimit: String = .empty
    @Published var baseFee: String = .empty
    @Published var totalFee: String = .empty
    @Published var selectedMode: FeeMode = .normal

    init(gasLimit: String, baseFee: String, totalFee: String, selectedMode: FeeMode) {
        self.gasLimit = gasLimit
        self.baseFee = baseFee
        self.totalFee = totalFee
        self.selectedMode = selectedMode
    }

    init(gasLimit: BigInt, selectedMode: FeeMode) {
        self.gasLimit = gasLimit.description
        self.selectedMode = selectedMode
    }

    var totalFeeFiat: String {
        return "$3.4"
    }
}
