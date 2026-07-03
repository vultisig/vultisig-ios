//
//  CosmosFeeFloorConfig.swift
//  VultisigApp
//
//  Per-chain Cosmos fee-floor + minimum-gas-price table.
//
//  Some Cosmos chains enforce a non-zero minimum gas price in their node ante
//  handler; a fee below `gasLimit × minGasPrice` is rejected on-chain with
//  "insufficient fee". This table is the single source of truth for the safe
//  floor, so the send path, the `Coin.feeDefault` fallback and the
//  dApp-injected signing path all agree on the same minimum — keeping the
//  displayed fee and the signed fee identical.
//
//  Akash (akashnet-2):
//    * node `--minimum-gas-prices` = 0.025 uakt/gas (Akash docs, step5 set
//      minimum gas price).
//    * cosmos chain-registry akash/chain.json `fixed_min_gas_price` = 0.025.
//    * 1 AKT = 1_000_000 uakt (6 decimals).
//    * `minFeeFloor` 25_000 uakt is a round 0.025 AKT safety floor matching the
//      Android / Windows clients (~3.3× the 300k-gas minimum of 7_500 uakt). It
//      is a client-implementation choice, not a registry constant.
//
//  Osmosis (osmosis-1): 25_000 uosmo, folded in from the previous inline
//  BlockChainService literal ("Increased from 7500 to prevent insufficient fee
//  errors"). `minGasPrice` 0 keeps the gas-price arm inert, so the flat 25_000
//  floor is preserved exactly.
//
//  Chains absent from the table are unconstrained — `flooredFee` returns the
//  computed fee unchanged (ATOM / Kujira / Noble / dYdX / Terra / TerraClassic
//  pay flat fees above their floors; QBTC has min_gas_price = 0).
//
//  If Akash is ever added to `CosmosStakingConfig`, its `feeAmount` must be
//  `>= minFeeFloor(.akash)` and ideally derived from this table, so the staking
//  fee stays consistent with the send / sign floor.
//

import Foundation

enum CosmosFeeFloorConfig {
    struct Entry {
        /// Minimum gas price, in fee-denom base units per gas unit.
        let minGasPrice: Decimal
        /// Absolute fee floor, in fee-denom base units.
        let minFeeFloor: UInt64
    }

    static let table: [Chain: Entry] = [
        .akash: Entry(minGasPrice: 0.025, minFeeFloor: 25_000),
        .osmosis: Entry(minGasPrice: 0, minFeeFloor: 25_000)
    ]

    /// Absolute fee floor for a chain — 0 when the chain enforces no floor.
    static func minFeeFloor(for chain: Chain) -> UInt64 {
        table[chain]?.minFeeFloor ?? 0
    }

    /// The required on-chain minimum fee for `chain` at `gasLimit`:
    /// `max(minFeeFloor, ceil(gasLimit × minGasPrice))`. Returns 0 for chains
    /// absent from the table.
    static func requiredFloor(for chain: Chain, gasLimit: UInt64) -> UInt64 {
        guard let entry = table[chain] else { return 0 }
        let gasPriceFee = ceilToUInt64(entry.minGasPrice * Decimal(gasLimit))
        return max(entry.minFeeFloor, gasPriceFee)
    }

    /// `max(computedFee, minFeeFloor, ceil(gasLimit × minGasPrice))`.
    /// Chains absent from the table return `computedFee` unchanged.
    static func flooredFee(for chain: Chain, computedFee: UInt64, gasLimit: UInt64) -> UInt64 {
        max(computedFee, requiredFloor(for: chain, gasLimit: gasLimit))
    }

    /// Whether `fee` (fee-denom base units) meets the chain's floor at
    /// `gasLimit`. Used to validate — never silently rewrite — a peer-shared
    /// `signDirect` fee, whose `authInfoBytes` both cosigners hash.
    static func meetsFloor(for chain: Chain, fee: UInt64, gasLimit: UInt64) -> Bool {
        fee >= requiredFloor(for: chain, gasLimit: gasLimit)
    }

    private static func ceilToUInt64(_ value: Decimal) -> UInt64 {
        guard value > 0 else { return 0 }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .up)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }
}
