//
//  MappablePayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.07.2024.
//

import Foundation
import SwiftProtobuf

protocol ProtoMappable {
    associatedtype ProtoType: SwiftProtobuf.Message
    init(protobuf: ProtoType, vault: Vault) throws
    func mapToProtobuff() -> ProtoType
}
