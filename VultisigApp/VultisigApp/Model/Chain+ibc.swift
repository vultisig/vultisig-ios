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
        case .kujira:
            return [
                IBCInfo(sourceChannel: "channel-0", destinationChain: .gaiaChain),
                IBCInfo(sourceChannel: "channel-64", destinationChain: .akash),
                IBCInfo(sourceChannel: "channel-118", destinationChain: .dydx),
                IBCInfo(sourceChannel: "channel-62", destinationChain: .noble),
                IBCInfo(sourceChannel: "channel-3", destinationChain: .osmosis)
            ]
        case .osmosis:
            return [
                IBCInfo(sourceChannel: "channel-0", destinationChain: .gaiaChain),
                IBCInfo(sourceChannel: "channel-259", destinationChain: .kujira)
            ]
        case .gaiaChain:
            return [
                IBCInfo(sourceChannel: "channel-141", destinationChain: .osmosis),
                IBCInfo(sourceChannel: "channel-343", destinationChain: .kujira)
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
