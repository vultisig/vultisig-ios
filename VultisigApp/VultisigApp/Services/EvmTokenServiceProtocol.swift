//
//  EvmTokenServiceProtocol.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 03/06/24.
//

import Foundation

protocol EvmTokenServiceProtocol {
    func getTokens(chain:Chain, address: String) async -> [Coin]
}
