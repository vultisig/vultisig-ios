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

class AkashHelper: CosmosHelper {
    
    init(){
        super.init(coinType: .akash, denom: "uakt", gasLimit: 200000)
    }
    
}
