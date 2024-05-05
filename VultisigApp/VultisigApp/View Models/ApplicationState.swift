//
//  ApplicationState.swift
//  VultisigApp
//

import SwiftUI

final class ApplicationState : ObservableObject {
    @Published var currentVault: Vault?
    
    // Singleton
    static let shared = ApplicationState()
    
    init() {}
}
