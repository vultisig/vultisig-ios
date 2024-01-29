//
//  ApplicationState.swift
//  VoltixApp
//

import Foundation

final class ApplicationState : ObservableObject {
    //@Published var example: Int = 1
    
    // Singleton
    static let shared = ApplicationState()
    private init() {}
}
