//
//  CosmosStakingSignDataResolver.swift
//  VultisigApp
//
//  Builds the SignDoc artefacts (bodyBytes, authInfoBytes, chainId,
//  accountNumber) for a Cosmos-SDK staking operation. Consumed by the
//  Verify → KeysignPayload bridge whenever
//  `SendTransaction.cosmosStakingPayload != nil`.
//
//  Each `opType` dispatches to the matching `CosmosStakingHelper.encode*`
//  call, packs the resulting `Any`-wrapped message(s) into a TxBody, and
//  pairs them with an AuthInfo derived from the chain's
//  `CosmosStakingConfig` entry. Gas + fee are scaled linearly with the
//  message count for the batched-claim path; single-msg flows use the
//  per-chain base values.
//
//  Validator-address preflight gating (bech32 / HRP / payload length) is
//  enforced HERE — before any SignDoc bytes are produced — so an invalid
//  validator throws at build time, never burning an MPC ceremony on a
//  chain-rejected tx (Spec Risk 5 + Decision 1B mitigation).
//

import Foundation
import OSLog

enum CosmosStakingSignDataResolver {
    enum Errors: Error, LocalizedError {
        case missingChainSpecific
        case invalidPublicKey
        case missingPayloadField(String)
        case validatorPreflightFailed(String)
        case noValidatorsToClaim

        var errorDescription: String? {
            switch self {
            case .missingChainSpecific:
                return "Missing Cosmos chain-specific account/sequence info for staking"
            case .invalidPublicKey:
                return "Invalid compressed secp256k1 public key for staking"
            case .missingPayloadField(let field):
                return "Cosmos staking payload missing required field: \(field)"
            case .validatorPreflightFailed(let reason):
                return "Validator address rejected by bech32 preflight: \(reason)"
            case .noValidatorsToClaim:
                return "Withdraw rewards requires at least one validator"
            }
        }
    }

    private static let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "cosmos-staking-sign-resolver"
    )

    /// Resolves the SignDoc artefacts for a staking payload. Caller passes
    /// the immutable `SendTransaction` and the Cosmos chain-specific
    /// (already populated upstream by `BlockChainService.fetchSpecific(...)`).
    static func resolve(
        sendTransaction: SendTransaction,
        chainSpecific: BlockChainSpecific
    ) throws -> SignDirect {
        guard let payload = sendTransaction.cosmosStakingPayload else {
            throw Errors.missingPayloadField("cosmosStakingPayload")
        }
        guard case .Cosmos(let accountNumber, let sequence, _, _, _) = chainSpecific else {
            throw Errors.missingChainSpecific
        }
        guard let pubKey = Data(hexString: sendTransaction.coin.hexPublicKey) else {
            throw Errors.invalidPublicKey
        }
        let chain = sendTransaction.coin.chain
        let entry = try CosmosStakingConfig.entry(for: chain)
        let delegator = sendTransaction.coin.address

        let msgsAny = try encodeMessages(
            payload: payload,
            chain: chain,
            delegator: delegator,
            denom: entry.bondDenom
        )

        // Linear gas + fee scaling for batched-claim — single-msg flows use
        // N=1 which collapses to the base config values.
        let multiplier = UInt64(max(msgsAny.count, 1))
        let gasLimit = entry.gasLimit * multiplier
        let feeAmount = entry.feeAmount * multiplier

        let bodyBytes = CosmosStakingHelper.buildTxBodyMulti(msgsAny: msgsAny, memo: "")
        let authInfoBytes = CosmosStakingHelper.buildAuthInfo(
            pubKey: pubKey,
            sequence: sequence,
            gasLimit: gasLimit,
            feeDenom: entry.feeDenom,
            feeAmount: feeAmount
        )

        logger.info(
            """
            Built Cosmos staking SignDoc: op=\(payload.opType.rawValue, privacy: .public) \
            chain=\(chain.rawValue, privacy: .public) msgs=\(msgsAny.count) \
            gas=\(gasLimit) fee=\(feeAmount)\(entry.feeDenom, privacy: .public)
            """
        )

        return SignDirect(
            bodyBytes: bodyBytes.base64EncodedString(),
            authInfoBytes: authInfoBytes.base64EncodedString(),
            chainID: entry.chainId,
            accountNumber: String(accountNumber)
        )
    }

    // MARK: - Per-op encoders

    private static func encodeMessages(
        payload: CosmosStakingPayload,
        chain: Chain,
        delegator: String,
        denom: String
    ) throws -> [Data] {
        switch payload.opType {
        case .delegate:
            return [try encodeDelegate(payload: payload, chain: chain, delegator: delegator, denom: denom)]
        case .undelegate:
            return [try encodeUndelegate(payload: payload, chain: chain, delegator: delegator, denom: denom)]
        case .redelegate:
            return [try encodeRedelegate(payload: payload, chain: chain, delegator: delegator, denom: denom)]
        case .withdrawRewards:
            return try encodeWithdrawRewards(payload: payload, chain: chain, delegator: delegator)
        }
    }

    private static func encodeDelegate(
        payload: CosmosStakingPayload,
        chain: Chain,
        delegator: String,
        denom: String
    ) throws -> Data {
        guard let validator = payload.validatorAddress, !validator.isEmpty else {
            throw Errors.missingPayloadField("validatorAddress")
        }
        guard let amount = payload.amount, !amount.isEmpty else {
            throw Errors.missingPayloadField("amount")
        }
        try preflight(validator: validator, chain: chain)
        return CosmosStakingHelper.encodeDelegate(
            delegator: delegator,
            validator: validator,
            amount: amount,
            denom: denom
        )
    }

    private static func encodeUndelegate(
        payload: CosmosStakingPayload,
        chain: Chain,
        delegator: String,
        denom: String
    ) throws -> Data {
        guard let validator = payload.validatorAddress, !validator.isEmpty else {
            throw Errors.missingPayloadField("validatorAddress")
        }
        guard let amount = payload.amount, !amount.isEmpty else {
            throw Errors.missingPayloadField("amount")
        }
        try preflight(validator: validator, chain: chain)
        return CosmosStakingHelper.encodeUndelegate(
            delegator: delegator,
            validator: validator,
            amount: amount,
            denom: denom
        )
    }

    private static func encodeRedelegate(
        payload: CosmosStakingPayload,
        chain: Chain,
        delegator: String,
        denom: String
    ) throws -> Data {
        guard let src = payload.validatorSrcAddress, !src.isEmpty else {
            throw Errors.missingPayloadField("validatorSrcAddress")
        }
        guard let dst = payload.validatorDstAddress, !dst.isEmpty else {
            throw Errors.missingPayloadField("validatorDstAddress")
        }
        guard let amount = payload.amount, !amount.isEmpty else {
            throw Errors.missingPayloadField("amount")
        }
        try preflight(validator: src, chain: chain)
        try preflight(validator: dst, chain: chain)
        return CosmosStakingHelper.encodeBeginRedelegate(
            delegator: delegator,
            validatorSrc: src,
            validatorDst: dst,
            amount: amount,
            denom: denom
        )
    }

    private static func encodeWithdrawRewards(
        payload: CosmosStakingPayload,
        chain: Chain,
        delegator: String
    ) throws -> [Data] {
        guard let validators = payload.validators, !validators.isEmpty else {
            throw Errors.noValidatorsToClaim
        }
        return try validators.map { validator in
            try preflight(validator: validator, chain: chain)
            return CosmosStakingHelper.encodeWithdrawDelegatorReward(
                delegator: delegator,
                validator: validator
            )
        }
    }

    // MARK: - Validator preflight

    private static func preflight(validator: String, chain: Chain) throws {
        do {
            try ValidatorBech32Preflight.validate(validator, for: chain)
        } catch {
            throw Errors.validatorPreflightFailed(error.localizedDescription)
        }
    }
}
