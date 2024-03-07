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
}
