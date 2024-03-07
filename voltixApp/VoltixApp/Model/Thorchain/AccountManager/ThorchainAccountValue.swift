//
//  ThorchainAccountValue.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainAccountValue: Codable {
    var address: String
    var accountNumber: String
    
    init(address: String, accountNumber: String) {
        self.address = address
        self.accountNumber = accountNumber
    }
}
