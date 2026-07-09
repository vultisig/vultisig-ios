//
//  SettingsCustomMessageViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 05.12.2024.
//

import Foundation

@MainActor
class SettingsCustomMessageViewModel: ObservableObject {

    enum KeysignState: Int, CaseIterable {
        case initial = 1
        case verify
        case pair
        case keysign
        case done

        var title: String {
            switch self {
            case .initial:
                return "Sign message".localized
            case .verify:
                return "verify".localized
            case .pair:
                return "pair".localized
            case .keysign:
                return "keysign".localized
            case .done:
                return "overview".localized
            }
        }
    }

    @Published var state: KeysignState = .initial
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
        case .initial, .verify, .pair:
            return true
        }
    }
}
