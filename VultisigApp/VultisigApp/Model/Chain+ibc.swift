//
//  Chain+IBC.swift
//  VultisigApp
//
//  Created by Enrique Souza 11.04.25
//

import Foundation

// https://github.com/cosmos/chain-registry/blob/master/_IBC/cosmoshub-osmosis.json
extension Chain {
    struct IBCInfo {
        let sourceChannel: String
        let destinationChain: Chain
    }

    var ibcTo: [IBCInfo] {
        switch self {
        case .osmosis:
            return [
                IBCInfo(sourceChannel: "channel-0", destinationChain: .gaiaChain)
            ]
        case .gaiaChain:
            return [
                IBCInfo(sourceChannel: "channel-141", destinationChain: .osmosis)
            ]
        default:
            return []
        }
    }

    func ibcChannel(to destination: Chain?) -> String? {
        if destination == nil {
            return nil
        }
        return ibcTo.first(where: { $0.destinationChain == destination })?.sourceChannel
    }
}
