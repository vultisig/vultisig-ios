//
//  ThorchainAccountNumberResponse.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainAccountNumberResponse: Codable {
    var height: String
    var result: ThorchainAccountResult
    
    init(height: String, result: ThorchainAccountResult) {
        self.height = height
        self.result = result
    }
}
