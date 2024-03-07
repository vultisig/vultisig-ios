//
//  ThorchainAccountResult.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainAccountResult: Codable {
    var type: String
    var value: ThorchainAccountValue
    
    init(type: String, value: ThorchainAccountValue) {
        self.type = type
        self.value = value
    }
}
