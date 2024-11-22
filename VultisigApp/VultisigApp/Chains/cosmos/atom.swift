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

class ATOMHelper: CosmosHelper {
    
    init(){
        super.init(coinType: .cosmos, denom: "uatom", gasLimit: 200000)
    }
    
}
