//
//  SettingsCustomMessageViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 05.12.2024.
//

import Foundation

@MainActor
class SettingsCustomMessageViewModel: ObservableObject, TransferViewModel {

    enum KeysignState: Int, CaseIterable {
        case initial = 1
        case pair
        case keysign
        case done

        var title: String {
            switch self {
            case .initial:
                return "Sign message"
            case .pair:
                return "pair"
            case .keysign:
                return "keysign"
            case .done:
                return "overview"
            }
        }
    }

    @Published var state: KeysignState = .initial
    @Published var hash: String?
    @Published var approveHash: String?
    @Published var currentIndex: Int = 1

    var progress: Double {
        return Double(currentIndex) / Double(KeysignState.allCases.count)
    }

    func moveToNextView() {
        currentIndex += 1
        state = KeysignState.allCases[currentIndex-1]
    }

    func handleBackTap() {
        currentIndex-=1
        state = KeysignState.allCases[currentIndex-1]
    }

    func canGoBack() -> Bool {
        switch state {
        case .done, .keysign:
            return false
        case .initial, .pair:
            return true
        }
    }
}
