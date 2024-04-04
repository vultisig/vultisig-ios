//
//  SwapCryptoViewModel.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 02.04.2024.
//

import SwiftUI

@MainActor
class SwapCryptoViewModel: ObservableObject {

    @Published var currentIndex = 1
    @Published var currentTitle = "send"

    let titles = ["send", "verify", "pair", "keysign", "done"]

    var progress: Double {
        Double(currentIndex) / Double(titles.count)
    }

    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }
}
