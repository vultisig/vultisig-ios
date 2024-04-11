//
//  UserDefaults.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 11/04/2024.
//

import Foundation

class UserPreferencesStore {
    static var currency: String {
        get {
            return UserDefaults.standard.string(forKey: "currency") ?? .empty
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "currency")
        }
    }
}

