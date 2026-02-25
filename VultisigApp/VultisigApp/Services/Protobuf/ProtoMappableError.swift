//
//  ProtoMappableError.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.07.2024.
//

import Foundation

enum ProtoMappableError: Error {
    case chainNotSupport
    case blockchainSpecificNotFound
    case base64EncodedDataNotFound
}
