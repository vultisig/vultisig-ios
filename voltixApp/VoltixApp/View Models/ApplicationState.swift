//
//  ApplicationState.swift
//  VoltixApp
//

import SwiftUI

final class ApplicationState : ObservableObject {
    @Published var currentVault: Vault?
    
    // field used during keygen process
    @Published var creatingVault: Vault?
    
    // Singleton
    static let shared = ApplicationState()
    
    init() {}
}
