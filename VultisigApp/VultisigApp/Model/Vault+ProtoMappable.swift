//
//  Vault+ProtoMapper.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/7/2024.
//

import Foundation
import VultisigCommonData
import SwiftProtobuf

extension BackupVault: ProtoMappableNoVault {
    init(proto: VSVaultContainer) throws {
        if proto.isEncrypted {
            
        } else {
            
        }
    }
    
    func mapToProtobuf() -> VSVaultContainer {
        return .with{
            $0.version = "v1"
        }
    }
}
