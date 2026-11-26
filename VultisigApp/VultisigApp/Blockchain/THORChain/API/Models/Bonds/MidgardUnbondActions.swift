//
//  MidgardUnbondActions.swift
//  VultisigApp
//

import Foundation

/// One page of a node's unbonds from Midgard's `/v2/actions?type=unbond`, newest
/// first, on THORChain and MayaChain alike. `MidgardAction` is not reused: it
/// requires fields an unbond lookup never reads and has no `bond` metadata.
struct MidgardUnbondActions: Decodable {
    struct Action: Decodable {
        struct Sender: Decodable {
            let address: String?
        }

        struct Metadata: Decodable {
            struct Bond: Decodable {
                let memo: String
                let nodeAddress: String
            }

            let bond: Bond
        }

        let height: String
        let `in`: [Sender]
        let metadata: Metadata

        /// The provider whose bond this reduced, lowercased. A node operator names it last
        /// in the memo (THORChain `UNBOND:<node>:<amount>:<provider>`, MayaChain
        /// `UNBOND:<asset>:<units>:<node>:<provider>`); otherwise the provider sent it.
        var provider: String? {
            let node = metadata.bond.nodeAddress.lowercased()
            let addressPrefix = node.prefix { $0 != "1" } + "1"
            if let last = metadata.bond.memo.split(separator: ":").last?.lowercased(),
               last != node,
               last.hasPrefix(addressPrefix) {
                return last
            }
            return self.in.first?.address?.lowercased()
        }
    }

    let actions: [Action]

    /// The heights of the unbonds of `bondAddress` from `nodeAddress` on this page.
    /// Throws when the page is full, since older unbonds may then be missing from it.
    func heights(of bondAddress: String, onNode nodeAddress: String) throws -> [Int] {
        guard actions.count < BondRewardHistoryConfig.unbondPageSize else {
            throw UnreadableUnbondHistory()
        }
        let bond = bondAddress.lowercased()
        let node = nodeAddress.lowercased()
        return try actions
            // An unbond whose provider can't be read is counted, so the walk stops there.
            .filter { $0.metadata.bond.nodeAddress.lowercased() == node && ($0.provider ?? bond) == bond }
            .map { action in
                guard let height = Int(action.height) else { throw UnreadableUnbondHistory() }
                return height
            }
    }
}

struct UnreadableUnbondHistory: Error {}
