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
    init(proto: ProtoType) throws
    func mapToProtobuff() -> ProtoType
}
