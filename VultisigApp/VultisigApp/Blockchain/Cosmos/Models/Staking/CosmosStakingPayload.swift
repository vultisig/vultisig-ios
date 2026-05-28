//
//  CosmosStakingPayload.swift
//  VultisigApp
//
//  Carries the staking-operation intent from the per-flow `TransactionBuilder`
//  through `SendTransaction` into the Verify → KeysignPayload bridge. At
//  build-keysign time the `CosmosStakingSignDataResolver` consumes this
//  payload, encodes the matching `Any`-wrapped Cosmos-SDK message via
//  `CosmosStakingHelper`, builds the SignDoc bytes, and writes
//  `KeysignPayload.signData = .signDirect(...)`.
//
//  Discriminated by `opType`. Field set per op:
//    .delegate            → validatorAddress, denom, amount
//    .undelegate          → validatorAddress, denom, amount
//    .redelegate          → validatorSrcAddress, validatorDstAddress, denom, amount
//    .withdrawRewards     → validators (1..N), denom
//
//  Local to iOS only — the proto-mappable bridge to `KeysignMessage` does NOT
//  round-trip this field. Same posture as `qbtcClaimPayload`; the SignDoc
//  bytes produced from it are what the peer device sees, and those bytes are
//  the contract.
//

import Foundation

enum CosmosStakingOpType: String, Codable, Hashable {
    case delegate
    case undelegate
    case redelegate
    case withdrawRewards
}

struct CosmosStakingPayload: Codable, Hashable {
    let opType: CosmosStakingOpType
    let validatorAddress: String?
    let validatorSrcAddress: String?
    let validatorDstAddress: String?
    let validators: [String]?
    let denom: String
    /// Base-unit string (e.g. `"1000000"` for 1 LUNA). `nil` for
    /// `.withdrawRewards` — `MsgWithdrawDelegatorReward` carries no Coin.
    let amount: String?

    static func delegate(validator: String, denom: String, amount: String) -> CosmosStakingPayload {
        CosmosStakingPayload(
            opType: .delegate,
            validatorAddress: validator,
            validatorSrcAddress: nil,
            validatorDstAddress: nil,
            validators: nil,
            denom: denom,
            amount: amount
        )
    }

    static func undelegate(validator: String, denom: String, amount: String) -> CosmosStakingPayload {
        CosmosStakingPayload(
            opType: .undelegate,
            validatorAddress: validator,
            validatorSrcAddress: nil,
            validatorDstAddress: nil,
            validators: nil,
            denom: denom,
            amount: amount
        )
    }

    static func redelegate(src: String, dst: String, denom: String, amount: String) -> CosmosStakingPayload {
        CosmosStakingPayload(
            opType: .redelegate,
            validatorAddress: nil,
            validatorSrcAddress: src,
            validatorDstAddress: dst,
            validators: nil,
            denom: denom,
            amount: amount
        )
    }

    static func withdrawRewards(validators: [String], denom: String) -> CosmosStakingPayload {
        CosmosStakingPayload(
            opType: .withdrawRewards,
            validatorAddress: nil,
            validatorSrcAddress: nil,
            validatorDstAddress: nil,
            validators: validators,
            denom: denom,
            amount: nil
        )
    }
}
