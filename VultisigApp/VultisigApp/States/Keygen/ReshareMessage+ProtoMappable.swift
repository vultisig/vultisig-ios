//
//  KeygenMessage+ProtoMappable.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 10.07.2024.
//

import Foundation
import VultisigCommonData

extension ReshareMessage: ProtoMappable {

    init(proto: VSReshareMessage) throws {
        self.sessionID = proto.sessionID
        self.hexChainCode = proto.hexChainCode
        self.serviceName = proto.serviceName
        self.pubKeyECDSA = proto.publicKeyEcdsa
        self.oldParties = proto.oldParties
        self.encryptionKeyHex = proto.encryptionKeyHex
        self.useVultisigRelay = proto.useVultisigRelay
        self.oldResharePrefix = proto.oldResharePrefix
        self.vaultName = proto.vaultName
        self.libType = proto.libType.toLibType()
    }

    func mapToProtobuff() -> VSReshareMessage {
        return .with {
            $0.sessionID = sessionID
            $0.hexChainCode = hexChainCode
            $0.serviceName = serviceName
            $0.publicKeyEcdsa = pubKeyECDSA
            $0.oldParties = oldParties
            $0.encryptionKeyHex = encryptionKeyHex
            $0.useVultisigRelay = useVultisigRelay
            $0.oldResharePrefix = oldResharePrefix
            $0.vaultName = vaultName
            $0.libType = libType.toVSLibType()
        }
    }
}
