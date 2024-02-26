//
//  WalletService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 25/02/2024.
//

import Foundation

class WalletService {
    private let coinHelper: CoinHelperProtocol
    
    init(coinHelper: CoinHelperProtocol) {
        self.coinHelper = coinHelper
    }
    
    func validateCryptoAddress(_ address: String) -> Bool {
        return coinHelper.validateAddress(address)
    }
}
