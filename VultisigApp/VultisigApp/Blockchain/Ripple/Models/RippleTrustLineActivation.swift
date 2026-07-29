//
//  RippleTrustLineActivation.swift
//  VultisigApp
//

import BigInt
import Foundation

/// What opening one XRPL trust line costs, and whether this account can afford
/// it.
///
/// Every ledger object an account owns — a trust line included — raises its
/// reserve floor by one **owner reserve increment**, and the increment is a
/// validator-voted network parameter (0.2 XRP on mainnet today, but a value, not
/// a constant). It is read live from `server_state`'s `reserve_inc` through the
/// existing live → cache → seed chain, so this never hardcodes it.
///
/// Kept a pure value type so the affordability rule can be pinned without a
/// network round-trip.
struct RippleTrustLineActivationQuote: Equatable {
    /// Live owner-reserve increment in drops — the XRP this trust line locks up
    /// for as long as it exists.
    let ownerReserveDrops: BigInt
    /// Transaction fee in drops for the TrustSet itself.
    let feeDrops: BigInt
    /// Spendable XRP in drops. The XRP coin's balance is ALREADY reserve-net
    /// (`RippleService.getBalance` subtracts the current floor), so this is what
    /// is genuinely available to newly lock up and spend.
    let spendableDrops: BigInt
    /// The trust-line limit that will be signed, as the XRPL value string that
    /// goes on the wire — shown so the signed limit is never invisible.
    let limitValue: String
    /// On-ledger currency code being trusted.
    let currencyCode: String
    /// Issuer whose currency is being trusted.
    let issuer: String

    /// Total XRP this activation consumes: the reserve it locks up plus the fee
    /// it burns. The reserve is not spent — it is immobilized — but from the
    /// user's spendable balance both come out the same way.
    var totalCostDrops: BigInt {
        ownerReserveDrops + feeDrops
    }

    /// Spendable XRP once the line exists. Never negative: an unaffordable
    /// activation is reported by `isAffordable`, not by a negative balance.
    var remainingSpendableDrops: BigInt {
        max(spendableDrops - totalCostDrops, BigInt(0))
    }

    /// Whether spendable XRP covers `reserve_inc + fee`. Below this the TrustSet
    /// fails on-ledger (`tecINSUFFICIENT_RESERVE`) after the ceremony, with the
    /// fee already burned — so it must block before signing starts.
    var isAffordable: Bool {
        spendableDrops >= totalCostDrops
    }

    /// Human-readable ticker for the currency being trusted.
    var currencyTicker: String {
        RippleIssuedCurrency.toIssuedCurrencyTicker(currencyCode)
    }
}
