//
//  VoteOption.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 28/06/24.
//

import Foundation
import WalletCore

// Extend TW_Cosmos_Proto_Message.VoteOption to conform to Identifiable and Equatable
extension TW_Cosmos_Proto_Message.VoteOption: @retroactive Identifiable {
    public var id: Int {
        return self.rawValue
    }

    public var description: String {
        switch self {
        case .unspecified:
            return "Unspecified"
        case .yes:
            return "Yes"
        case .abstain:
            return "Abstain"
        case .no:
            return "No"
        case .noWithVeto:
            return "No with Veto"
        case .UNRECOGNIZED(let value):
            return "Unrecognized (\(value))"
        @unknown default:
            return "Unknown"
        }
    }
}
