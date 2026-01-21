//
//  SheetPresentedCounterManager.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/10/2025.
//

import Foundation

// Observable object to manage sheet counter state
class SheetPresentedCounterManager: ObservableObject {
    @Published var counter: Int = 0
    
    func increment() {
        self.counter += 1
    }
    
    func decrement() {
        guard counter > 0 else { return }
        self.counter -= 1
    }
    
    func resetCounter() {
        self.counter = 0
    }
}
