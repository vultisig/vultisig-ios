
//
//  Chain+IBC.swift
//  VultisigApp
//
//  Created by Enrique Souza 11.04.25
//

import Foundation

extension Chain {
    struct IBCInfo {
        let sourceChannel: String
        let destinationChain: Chain
    }

    var ibcTo: [IBCInfo] {
        switch self {
        case .kujira:
            return [
                IBCInfo(sourceChannel: "channel-0", destinationChain: .gaiaChain)
            ]
        case .osmosis:
            return [
                IBCInfo(sourceChannel: "channel-141", destinationChain: .gaiaChain)
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
