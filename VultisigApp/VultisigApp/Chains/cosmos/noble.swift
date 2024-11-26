//
//  atom.swift
//  VultisigApp
//
//  Created by Johnny Luo on 1/4/2024.
//

import Foundation
import WalletCore
import Tss
import CryptoSwift

class NobleHelper: CosmosHelper {
    
    init(){
        super.init(coinType: .noble, denom: "uusdc", gasLimit: 200000)
    }
    
}
