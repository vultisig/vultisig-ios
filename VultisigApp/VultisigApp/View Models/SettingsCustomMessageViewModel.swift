//
//  SettingsCustomMessageViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 05.12.2024.
//

import Foundation

@MainActor
class SettingsCustomMessageViewModel: ObservableObject, TransferViewModel {

    enum KeysignState {
        case initial
        case keysign
    }

    @Published var state: KeysignState = .initial
    @Published var hash: String?
    @Published var approveHash: String?

    func moveToNextView() {
        state = .keysign
    }
}
