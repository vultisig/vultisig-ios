//
//  ThorchainSwapProvider.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 06.06.2024.
//

import Foundation

protocol ThorchainSwapProvider {
    func fetchSwapQuotes(address: String, fromAsset: String, toAsset: String, amount: String, interval: Int, isAffiliate: Bool) async throws -> ThorchainSwapQuote
}
