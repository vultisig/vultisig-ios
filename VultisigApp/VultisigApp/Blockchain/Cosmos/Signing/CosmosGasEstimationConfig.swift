//
//  CosmosGasEstimationConfig.swift
//  VultisigApp
//
//  Scope for INITIATOR-set dynamic Cosmos gas estimation.
//

import Foundation

/// Decides which chains the initiator simulates (`/cosmos/tx/v1beta1/simulate`)
/// to derive a dynamic per-tx gas limit it relays to co-signers in proto
/// `CosmosSpecific.gas_limit`, for a more accurate gas limit than the static
/// per-chain fallback.
///
/// Two-sided contract:
///  * Read/honor side — ALWAYS-ON and hash-safe. Every Cosmos signing helper
///    applies a relayed `gas_limit` when present and falls back to the static
///    per-chain limit otherwise: `CosmosHelperStruct`, `TerraHelperStruct`,
///    `DydxHelperStruct`. It is a no-op when no peer set one, so two co-signing
///    devices always resolve the identical gas value.
///  * Initiator-set side — this type. The device simulates and SETS
///    `gas_limit`. The relayed value is part of the SignDoc every co-signer
///    hashes.
///
/// Enabled for every Cosmos-family chain that can be simulated through
/// WalletCore's secp256k1 Cosmos signing path. `.qbtc` is excluded: it signs
/// with ML-DSA keys via a bespoke builder (`QBTCHelper`) that WalletCore cannot
/// compile, so it cannot produce simulate `tx_bytes`.
///
/// CROSS-PLATFORM PARITY — KNOWN FOLLOW-UP. The other co-signers (`vultiserver`
/// / FastVault, `vultisig-android`, `vultisig-windows` / the browser extension,
/// `vultisig-sdk`) must also honor `gas_limit`. Until they ship the read side, a
/// Cosmos send co-signed across platforms where one side ignores the relayed
/// limit will diverge the SignDoc and fail the MPC signature. This is a
/// deliberate, tracked tradeoff — the relayed value is fail-closed (any
/// simulation error falls back to the static limit) and the PR stays draft
/// pending the cross-client work.
enum CosmosGasEstimationConfig {
    /// Cosmos chains that cannot be simulated via WalletCore (ML-DSA keys /
    /// bespoke builder), so the initiator never simulates them.
    static let nonSimulatableChains: Set<Chain> = [.qbtc]

    /// Whether the initiator should simulate gas for `chain` on a native send.
    static func shouldSimulate(chain: Chain) -> Bool {
        chain.chainType == .Cosmos && !nonSimulatableChains.contains(chain)
    }
}
