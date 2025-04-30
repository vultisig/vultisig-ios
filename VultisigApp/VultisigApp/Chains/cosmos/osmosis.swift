//
//  Osmosis.swift
//  VultisigApp
//
//  Created by Enrique Souza 29/10/2024
//

import Foundation
import WalletCore
import Tss
import CryptoSwift

class OsmoHelper: CosmosHelper {
    
    init(){
        super.init(coinType: .osmosis, denom: "uosmo", gasLimit: 300000)
    }
    
}
