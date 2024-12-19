//
//  kujira.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/04/2024.
//

import Foundation
import WalletCore
import Tss
import CryptoSwift

class KujiraHelper: CosmosHelper {
    
    init(){
        super.init(coinType: .kujira, denom: "ukuji", gasLimit: 300000)
    }
    
}
