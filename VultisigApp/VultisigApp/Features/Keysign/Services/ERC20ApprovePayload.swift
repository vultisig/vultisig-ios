//
//  ERC20ApprovePayload.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 22.04.2024.
//

import Foundation
import BigInt

struct ERC20ApprovePayload: Codable, Hashable {
    let amount: BigInt
    let spender: String
    /// The ERC-20 token whose allowance is being set (the `approve` call's
    /// target contract). Empty means "fall back to the keysign coin's
    /// `contractAddress`" — the historical behaviour for swap approves, where
    /// the keysign coin already IS the token being approved. A non-empty value
    /// lets a native-coin keysign (e.g. a deposit whose `coin` is native ETH)
    /// target a different token (USDC) for the approve leg.
    let token: String

    init(amount: BigInt, spender: String, token: String = "") {
        self.amount = amount
        self.spender = spender
        self.token = token
    }

    // Custom decoder for back-compat: older serialized payloads predate `token`
    // and must still decode (default to empty → coin-contract fallback).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.amount = try container.decode(BigInt.self, forKey: .amount)
        self.spender = try container.decode(String.self, forKey: .spender)
        self.token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
    }
}
