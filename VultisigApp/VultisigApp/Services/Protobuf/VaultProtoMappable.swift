//
//  VaultProtoMappable.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/7/2024.
//

import Foundation
import SwiftProtobuf

protocol ProtoMappableNoVault {
    associatedtype ProtoType: SwiftProtobuf.Message
    init(proto: ProtoType) throws
    func mapToProtobuff() -> ProtoType
}
