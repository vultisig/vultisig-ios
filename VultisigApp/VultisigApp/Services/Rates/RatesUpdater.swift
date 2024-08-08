//
//  RatesUpdater.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.08.2024.
//

import Foundation

class RatesUpdater: ObservableObject {
    static let shared = RatesUpdater()

    init() {
        RateProvider.shared.subscribe { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
