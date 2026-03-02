//
//  SignSolana.swift
//  VultisigApp
//
//  Created by Claude on 21/01/2025.
//

import VultisigCommonData

struct SignSolana: Codable, Hashable {
    let rawTransactions: [String]  // base64 encoded

    init(proto: VSSignSolana) {
        self.rawTransactions = proto.rawTransactions
    }

    func mapToProtobuff() -> VSSignSolana {
        .with {
            $0.rawTransactions = rawTransactions
        }
    }
}
