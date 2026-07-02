//
//  CosmosGasPricedFee.swift
//  VultisigApp
//
//  Shared re-derivation for Cosmos chains whose fee AMOUNT is priced per unit
//  of gas (`fee = gasLimit × minGasPrice`).
//
//  Some Cosmos chains (Terra Classic, dYdX) set the fee amount in
//  `chainSpecific.gas` to exactly `staticGasLimit × minGasPrice` — leaving zero
//  headroom over the ante handler's `fee >= gas_wanted × minGasPrice` check. The
//  signer, however, now signs a DYNAMIC `gas_wanted` (the relayed simulated
//  limit) while the static amount stays priced at the fixed limit, so once the
//  simulated limit exceeds the static one the signed fee undershoots and the tx
//  is rejected on-chain ("insufficient fee").
//
//  These chains are absent from `CosmosFeeFloorConfig` (whose `flooredFee`
//  re-derives Akash / Osmosis amounts from the effective limit), so the amount
//  must be re-derived here instead. Scaling the known-sufficient static amount
//  by the gas-limit ratio yields exactly `ceil(effectiveGasLimit × minGasPrice)`
//  without hardcoding each chain's price: the price is implicit in the static
//  amount. Because it is a pure function of the relayed limit and static
//  constants — no per-device or simulation-time state — co-signers derive
//  byte-identical fees.
//

import Foundation

enum CosmosGasPricedFee {

    /// Scale a fee priced at `fromGasLimit` gas to `toGasLimit` gas, rounded UP:
    /// `ceil(base × toGasLimit / fromGasLimit)`.
    ///
    /// When `base == fromGasLimit × pricePerGas`, this equals
    /// `ceil(toGasLimit × pricePerGas)` — the ante handler's required minimum at
    /// the signed `gas_wanted` — so the re-derived fee tracks the signed limit
    /// exactly. Returns `base` unchanged when the limit is unchanged (so the
    /// non-simulated path is byte-identical) or when `fromGasLimit` is 0.
    static func scaled(base: UInt64, fromGasLimit: UInt64, toGasLimit: UInt64) -> UInt64 {
        guard fromGasLimit > 0, toGasLimit != fromGasLimit else { return base }
        var product = Decimal(base) * Decimal(toGasLimit) / Decimal(fromGasLimit)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 0, .up)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }
}
