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
    /// Asks every signer to send `approve(spender, 0)` before
    /// `approve(spender, amount)`. Tokens such as USDT revert a non-zero to
    /// non-zero approve while a stale allowance remains.
    let resetAllowanceFirst: Bool

    init(amount: BigInt, spender: String, resetAllowanceFirst: Bool = false) {
        self.amount = amount
        self.spender = spender
        self.resetAllowanceFirst = resetAllowanceFirst
    }

    /// The amount of each approve leg, in nonce order. Each leg takes one nonce
    /// from the payload's onwards, and every signer derives the same list, so
    /// this is the cross-device contract.
    var legAmounts: [BigInt] {
        resetAllowanceFirst ? [.zero, amount] : [amount]
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case spender
        case resetAllowanceFirst
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.amount = try container.decode(BigInt.self, forKey: .amount)
        self.spender = try container.decode(String.self, forKey: .spender)
        // Absent from anything encoded before the reset existed.
        self.resetAllowanceFirst = try container.decodeIfPresent(Bool.self, forKey: .resetAllowanceFirst) ?? false
    }
}

extension KeysignPayload {
    /// Nonces the approve legs take ahead of the transaction that depends on
    /// the allowance: 2 with a reset, 1 without, 0 when there is no approve.
    var approveNonceOffset: Int64 {
        Int64(approvePayload?.legAmounts.count ?? 0)
    }
}
