//
//  TonStakePayload.swift
//  VultisigApp
//

import Foundation

/// App-initiated TonConnect-style message intent for the Tonstakers liquid
/// staking flows (deposit, unstake). Carried locally on `SendTransaction`
/// (mirroring `cosmosStakingPayload`) and consumed by the Verify →
/// KeysignPayload bridge, which attaches it as `.signTon(SignTon(tonMessages:))`
/// so both MPC devices sign the identical body BOC via the existing TonConnect
/// `customPayload` path. Local-only on iOS — does not round-trip through the
/// proto-mappable `KeysignMessage` bridge.
struct TonStakePayload: Hashable {
    let messages: [TonMessage]
}
