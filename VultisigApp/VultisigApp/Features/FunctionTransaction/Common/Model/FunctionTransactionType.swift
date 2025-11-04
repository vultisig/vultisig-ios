//
//  FunctionTransactionType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

enum FunctionTransactionType: Hashable {
    case bond(node: String?)
    case unbond(node: BondNode)
}
