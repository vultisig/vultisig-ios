//
//  CosmosCoin.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import VultisigCommonData

struct CosmosCoin: Codable, Hashable {
    let amount: String
    let denom: String
    
    init(proto: VSCosmosCoin) {
        self.amount = proto.amount
        self.denom = proto.denom
    }
    
    func mapToProtobuff() -> VSCosmosCoin {
        .with {
            $0.amount = self.amount
            $0.denom = self.denom
        }
    }
}
