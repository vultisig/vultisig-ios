//
//  SendCryptoViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

class SendCryptoViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var currentIndex = 1
    @Published var currentTitle = "send"
    
    let totalViews = 7
    let titles = ["send", "scan", "send", "pair", "verify", "keysign", "done"]
    
    func reloadTransactions() {
        
    }
    
    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex]
    }
    
    func getProgress() -> Double {
        Double(currentIndex)/Double(totalViews)
    }
}
