//
//  TonMessage.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

struct TonMessage: Codable, Hashable {
    let to: String
    let amount: String
    let payload: String?
    let stateInit: String?

    init(
        to: String,
        amount: String,
        payload: String? = nil,
        stateInit: String? = nil
    ) {
        self.to = to
        self.amount = amount
        self.payload = payload
        self.stateInit = stateInit
    }

    init(proto: VSTonMessage) {
        self.to = proto.to
        self.amount = proto.amount
        self.payload = proto.hasPayload ? proto.payload : nil
        self.stateInit = proto.hasStateInit ? proto.stateInit : nil
    }

    func mapToProtobuff() -> VSTonMessage {
        .with {
            $0.to = self.to
            $0.amount = self.amount
            if let payload = self.payload {
                $0.payload = payload
            }
            if let stateInit = self.stateInit {
                $0.stateInit = stateInit
            }
        }
    }
}
