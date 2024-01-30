//
//  ApplicationState.swift
//  VoltixApp
//

import SwiftUI

final class ApplicationState : ObservableObject {
    @Published var currentVault: Vault?
    
    // Singleton
    static let shared = ApplicationState()
    private init() {
        
    }
}
