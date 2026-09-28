//
//  BondRewardMath.swift
//  VultisigApp
//
//  The bond-provider award share, factored out of
//  `THORChainAPIService+Bonds.calculateBondMetrics` so THOR and Maya's live
//  metrics and the reward-history sheet's per-churn amounts compute the
//  identical number the identical way. Chain-agnostic: callers normalize
//  their own provider list (`String` amounts, `pools` sums, …) into
//  `(bondAddress, bond: Decimal)` first.
//

import Foundation

enum BondRewardMath {
    struct Share: Equatable {
        let myBond: Decimal
        let myAward: Decimal
    }

    /// `nil` when `myBondAddress` is not among `providers` — the address was
    /// not a bond provider at whatever snapshot `providers` describes.
    static func share(
        providers: [(bondAddress: String, bond: Decimal)],
        nodeOperatorFeeBps: Decimal,
        currentAward: Decimal,
        myBondAddress: String
    ) -> Share? {
        guard let myBond = providers.first(where: { $0.bondAddress == myBondAddress })?.bond else {
            return nil
        }

        let totalBond = providers.reduce(Decimal.zero) { $0 + $1.bond }
        guard totalBond > 0 else {
            return Share(myBond: myBond, myAward: 0)
        }

        let netAward = currentAward * (1 - nodeOperatorFeeBps / 10000)
        return Share(myBond: myBond, myAward: netAward * (myBond / totalBond))
    }
}
