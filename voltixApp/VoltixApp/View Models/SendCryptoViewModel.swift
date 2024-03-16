//
//  SendCryptoViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI

class SendCryptoViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var tabIndex = 1
    
    let totalViews = 7
    
    func reloadTransactions() {
        
    }
    
    func moveToNextView() {
        tabIndex += 1
    }
    
    func getProgress() -> Double {
        Double(tabIndex)/Double(totalViews)
    }
}
