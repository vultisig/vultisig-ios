//
//  YieldPosition.swift
//  VultisigApp
//

import Foundation
import SwiftData

/// Persisted cache of a DeFi yield-vault position, keyed `(providerID, pubKeyECDSA)`.
/// Generalizes the former `CirclePosition` so Circle and Noon share one cache;
/// extended with redemption rows for windowed (Noon) redemptions.
@Model
final class YieldPosition {
    @Attribute(.unique) var id: String

    var providerRawID: String
    var depositedBalance: Decimal
    var nativeGasBalance: Decimal
    var lastUpdated: Date

    @Relationship(deleteRule: .cascade, inverse: \YieldRedemptionRecord.position)
    var redemptions: [YieldRedemptionRecord] = []

    @Relationship(inverse: \Vault.yieldPositions) var vault: Vault?

    var providerID: DefiYieldProviderID? {
        DefiYieldProviderID(rawValue: providerRawID)
    }

    init(
        providerID: DefiYieldProviderID,
        depositedBalance: Decimal,
        nativeGasBalance: Decimal,
        vault: Vault
    ) {
        self.providerRawID = providerID.rawValue
        self.depositedBalance = depositedBalance
        self.nativeGasBalance = nativeGasBalance
        self.lastUpdated = .now
        self.vault = vault
        self.id = Self.makeID(providerID: providerID, pubKeyECDSA: vault.pubKeyECDSA)
    }

    static func makeID(providerID: DefiYieldProviderID, pubKeyECDSA: String) -> String {
        "\(providerID.rawValue)_\(pubKeyECDSA)"
    }
}

/// One windowed-redemption row attached to a `YieldPosition`. Circle positions
/// carry none (instant withdraw); Noon carries pending/claimable rows.
@Model
final class YieldRedemptionRecord {
    @Attribute(.unique) var id: String

    var amount: Decimal
    var requestedAt: Date
    var claimableAt: Date?
    var statusRawValue: String

    var position: YieldPosition?

    var status: YieldRedemption.Status {
        get { YieldRedemption.Status(rawValue: statusRawValue) ?? .none }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: String,
        amount: Decimal,
        requestedAt: Date,
        claimableAt: Date?,
        status: YieldRedemption.Status
    ) {
        self.id = id
        self.amount = amount
        self.requestedAt = requestedAt
        self.claimableAt = claimableAt
        self.statusRawValue = status.rawValue
    }
}
