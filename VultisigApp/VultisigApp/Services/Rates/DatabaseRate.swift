//
//  Rate.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.08.2024.
//

import Foundation
import SwiftData

@Model
final class DatabaseRate {

    @Attribute(.unique) var id: String
    
    let fiat: String
    let crypto: String
    let value: Double

    init(id: String, fiat: String, crypto: String, value: Double) {
        self.id = id
        self.fiat = fiat
        self.crypto = crypto
        self.value = value
    }
}
