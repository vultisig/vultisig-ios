//
//  SolanaMoveStakeCapability.swift
//  VultisigApp
//
//  Future-optimization capability probe for native single-transaction move
//  stake (SIMD-0148 `MoveStake` / `MoveLamports`). These instructions would
//  collapse the guided deactivate-and-re-delegate cycle into one transaction,
//  but they are NOT the v1 path:
//
//    * The native `Redelegate` instruction's feature gate was never activated
//      on mainnet and is not expected to be.
//    * wallet-core's high-level Solana proto exposes no Split / MoveStake /
//      MoveLamports instruction, so the app cannot build one with the
//      cross-device byte-parity guarantee TSS co-signing requires.
//
//  This probe is therefore documented and OFF BY DEFAULT. v1 ALWAYS takes the
//  guided split → deactivate → wait → re-delegate path. The flag exists only so
//  the seam is explicit for a future PR that wires a verified native path; it
//  is intentionally not read by the live flow.
//

import Foundation

enum SolanaMoveStakeCapability {
    /// Whether the live move-stake flow may use the native SIMD-0148
    /// `MoveStake` / `MoveLamports` single-transaction path. Always `false` in
    /// v1 — the guided deactivate-and-re-delegate flow is the only supported
    /// path. Do not flip without a byte-parity-verified native builder.
    static let supportsNativeMoveStake = false
}
