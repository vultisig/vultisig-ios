//
//  ERC20ApprovePayload.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 22.04.2024.
//

import Foundation
import BigInt

struct ERC20ApprovePayload: Codable, Hashable {
    let amount: BigInt
    let spender: String
}
