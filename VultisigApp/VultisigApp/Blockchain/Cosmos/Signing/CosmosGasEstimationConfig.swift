//
//  CosmosGasEstimationConfig.swift
//  VultisigApp
//
//  Master gate for INITIATOR-set dynamic Cosmos gas estimation.
//

import Foundation

/// Gate for the initiator-set side of relayed dynamic Cosmos gas estimation
/// (proto `CosmosSpecific.gas_limit`).
///
/// IMPORTANT — keep `isInitiatorDynamicGasEnabled` false until EVERY co-signing
/// implementation honors `gas_limit`: `vultiserver` (FastVault server
/// co-signer), `vultisig-android`, `vultisig-windows` / the browser extension,
/// and `vultisig-sdk`. The relayed gas limit is part of the SignDoc; if this
/// device sets it but a co-signer ignores it, the two SignDocs diverge and the
/// MPC signature fails — breaking FastVault and cross-client Cosmos signing in
/// production. Flip this flag only after all of those repos have shipped the
/// read/honor side.
///
/// The read/honor side (`CosmosHelperStruct.defaultFee`) is always-on and
/// unaffected by this flag: it is harmless when no peer sets a `gas_limit`.
enum CosmosGasEstimationConfig {
    /// Master gate. Defaults OFF. See the type doc for the enable precondition.
    static let isInitiatorDynamicGasEnabled = false

    /// Chains the initiator may simulate when the gate is on. Restricted to
    /// Akash (Phase-1 scope): chains here MUST route through
    /// `CosmosHelperStruct` (whose `defaultFee` honors the relayed limit) and
    /// have a `CosmosFeeFloorConfig` entry (so the floored fee is computed from
    /// a known minimum gas price). Terra / Dydx / QBTC use their own helpers
    /// that do not read `gas_limit`, so they are intentionally excluded.
    static let simulationChains: Set<Chain> = [.akash]

    /// Whether the initiator should simulate gas for `chain` for a native send.
    static func shouldSimulate(chain: Chain) -> Bool {
        isInitiatorDynamicGasEnabled && simulationChains.contains(chain)
    }
}
