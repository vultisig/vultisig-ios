//
//  ThorchainAccountResult.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class CosmosAccountResult: Codable {
    var type: String
    var value: CosmosAccountValue?
}

class CosmosAccountsResponse: Codable {
    var account: CosmosAccountValue
}
