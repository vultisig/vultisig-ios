//
//  SingleKeygenType.swift
//  VultisigApp
//

import VultisigCommonData
import Foundation

enum SingleKeygenType: Int, Codable, CaseIterable {
    case MLDSA = 0

    func toVSSingleKeygenType() -> VSSingleKeygenType {
        switch self {
        case .MLDSA:
            return .mldsa
        }
    }
}

extension VSSingleKeygenType {
    func toSingleKeygenType() throws -> SingleKeygenType {
        switch self {
        case .mldsa:
            return .MLDSA
        default:
            throw HelperError.runtimeError("Unknown VSSingleKeygenType: \(self)")
        }
    }
}
