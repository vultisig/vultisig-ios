//
//  SignTon.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

struct SignTon: Codable, Hashable {
    let tonMessages: [TonMessage]

    init(tonMessages: [TonMessage]) {
        self.tonMessages = tonMessages
    }

    init(proto: VSSignTon) {
        self.tonMessages = proto.tonMessages.map { TonMessage(proto: $0) }
    }

    func mapToProtobuff() -> VSSignTon {
        .with {
            $0.tonMessages = tonMessages.map { $0.mapToProtobuff() }
        }
    }
}
