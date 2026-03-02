//
//  SingleKeygenMessage+ProtoMappable.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

extension SingleKeygenMessage: ProtoMappable {

    init(proto: VSSingleKeygenMessage) throws {
        self.sessionID = proto.sessionID
        self.hexChainCode = proto.hexChainCode
        self.serviceName = proto.serviceName
        self.pubKeyECDSA = proto.publicKeyEcdsa
        self.oldParties = proto.oldParties
        self.encryptionKeyHex = proto.encryptionKeyHex
        self.useVultisigRelay = proto.useVultisigRelay
        self.vaultName = proto.vaultName
        self.libType = proto.libType.toLibType()
        self.singleKeygenType = proto.singleKeygenType.toSingleKeygenType()
    }

    func mapToProtobuff() -> VSSingleKeygenMessage {
        return .with {
            $0.sessionID = sessionID
            $0.hexChainCode = hexChainCode
            $0.serviceName = serviceName
            $0.publicKeyEcdsa = pubKeyECDSA
            $0.oldParties = oldParties
            $0.encryptionKeyHex = encryptionKeyHex
            $0.useVultisigRelay = useVultisigRelay
            $0.vaultName = vaultName
            $0.libType = libType.toVSLibType()
            $0.singleKeygenType = singleKeygenType.toVSSingleKeygenType()
        }
    }
}
