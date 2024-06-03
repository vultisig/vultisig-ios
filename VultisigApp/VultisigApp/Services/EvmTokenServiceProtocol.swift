//
//  EvmTokenServiceProtocol.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 03/06/24.
//

import Foundation

protocol EvmTokenServiceProtocol {
    func getTokens(address: String) async -> [Token]
}
