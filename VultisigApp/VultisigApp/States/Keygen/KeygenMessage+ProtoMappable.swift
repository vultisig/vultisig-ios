//
//  KeygenMessage+ProtoMappable.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.07.2024.
//

import Foundation
import VultisigCommonData

extension KeygenMessage: ProtoMappable {

    init(proto: VSKeygenMessage) throws {
        self.sessionID = proto.sessionID
        self.hexChainCode = proto.hexChainCode
        self.serviceName = proto.serviceName
        self.encryptionKeyHex = proto.encryptionKeyHex
        self.useVultisigRelay = proto.useVultisigRelay
        self.vaultName = proto.vaultName
    }

    func mapToProtobuff() -> VSKeygenMessage {
        return .with {
            $0.sessionID = sessionID
            $0.hexChainCode = hexChainCode
            $0.serviceName = serviceName
            $0.encryptionKeyHex = encryptionKeyHex
            $0.useVultisigRelay = useVultisigRelay
            $0.vaultName = vaultName
        }
    }
}
