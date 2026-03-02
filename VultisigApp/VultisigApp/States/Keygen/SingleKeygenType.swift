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
    func toSingleKeygenType() -> SingleKeygenType {
        switch self {
        case .mldsa:
            return .MLDSA
        default:
            return .MLDSA
        }
    }
}
