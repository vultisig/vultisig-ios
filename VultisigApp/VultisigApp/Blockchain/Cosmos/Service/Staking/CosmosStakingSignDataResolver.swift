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
    /// Hard cap on validators in a single batched withdraw-rewards tx.
    /// Mirrors the UI soft cap (`CosmosWithdrawRewardsTransactionViewModel.maxBatchSize`)
    /// — enforced again here so the resolver cannot be bypassed by upstream
    /// callers wiring payloads directly (Spec D-9 defense-in-depth).
    static let maxBatchWithdrawValidators = 8

    enum Errors: Error, LocalizedError {
        case missingChainSpecific
        case invalidPublicKey
        case missingPayloadField(String)
        case validatorPreflightFailed(String)
        case noValidatorsToClaim
        case tooManyValidatorsToClaim(max: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case .missingChainSpecific:
                return "cosmosStakingErrorMissingChainSpecific".localized
            case .invalidPublicKey:
                return "cosmosStakingErrorInvalidPublicKey".localized
            case .missingPayloadField(let field):
                return String(format: "cosmosStakingErrorMissingPayloadField".localized, field)
            case .validatorPreflightFailed(let reason):
                return String(format: "cosmosStakingErrorValidatorPreflightFailed".localized, reason)
            case .noValidatorsToClaim:
                return "cosmosStakingErrorNoValidatorsToClaim".localized
            case .tooManyValidatorsToClaim(let max, let actual):
                return String(
                    format: "cosmosStakingErrorTooManyValidatorsToClaim".localized,
                    max,
                    actual
                )
            }
        }
    }

    private static let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "cosmos-staking-sign-resolver"
    )

    /// Resolves the SignDoc artefacts for a secp256k1 staking payload. Caller
    /// passes the immutable `SendTransaction` and the Cosmos chain-specific
    /// (already populated upstream by `BlockChainService.fetchSpecific(...)`).
    static func resolve(
        sendTransaction: SendTransaction,
        chainSpecific: BlockChainSpecific
    ) throws -> SignDirect {
        // Validate compressed secp256k1 shape (33 bytes, 0x02 / 0x03 prefix)
        // *before* building AuthInfo — malformed keys would otherwise burn an
        // MPC ceremony and be rejected on-chain after signing.
        guard let pubKey = Data(hexString: sendTransaction.coin.hexPublicKey),
              pubKey.count == 33,
              pubKey.first == 0x02 || pubKey.first == 0x03
        else {
            throw Errors.invalidPublicKey
        }
        return try buildSignDirect(
            sendTransaction: sendTransaction,
            chainSpecific: chainSpecific,
            pubKey: pubKey,
            pubKeyTypeURL: CosmosStakingHelper.pubKeyTypeURL
        )
    }

    /// QBTC variant. QBTC signs with ML-DSA (post-quantum), so its pubkey is
    /// ~1312 bytes — the secp256k1 33-byte guard above would reject it. The
    /// staking msg bodies are pubkey-agnostic, so the ONLY differences are
    /// skipping that guard and stamping the ML-DSA pubkey type URL into
    /// AuthInfo. The resulting `signDirect` bytes round-trip through the proto
    /// so the peer device rebuilds the identical SignDoc hash; `QBTCHelper`
    /// consumes them directly instead of via WalletCore's secp256k1 compiler.
    static func resolveMLDSA(
        sendTransaction: SendTransaction,
        chainSpecific: BlockChainSpecific
    ) throws -> SignDirect {
        guard let pubKey = Data(hexString: sendTransaction.coin.hexPublicKey), !pubKey.isEmpty else {
            throw Errors.invalidPublicKey
        }
        return try buildSignDirect(
            sendTransaction: sendTransaction,
            chainSpecific: chainSpecific,
            pubKey: pubKey,
            pubKeyTypeURL: QBTCHelper.pubKeyTypeURL
        )
    }

    private static func buildSignDirect(
        sendTransaction: SendTransaction,
        chainSpecific: BlockChainSpecific,
        pubKey: Data,
        pubKeyTypeURL: String
    ) throws -> SignDirect {
        guard let payload = sendTransaction.cosmosStakingPayload else {
            throw Errors.missingPayloadField("cosmosStakingPayload")
        }
        guard case .Cosmos(let accountNumber, let sequence, _, _, _) = chainSpecific else {
            throw Errors.missingChainSpecific
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
        // N=1 which collapses to the base config values. Count comes from the
        // encoded messages; the `base × count` arithmetic is shared with the
        // verify screen via `CosmosStakingConfig` so the SIGNED fee here and
        // the DISPLAYED fee there can never drift.
        let msgCount = max(msgsAny.count, 1)
        let gasLimit = try CosmosStakingConfig.scaledGasLimit(for: chain, msgCount: msgCount)
        let feeAmount = try CosmosStakingConfig.scaledFeeAmount(for: chain, msgCount: msgCount)

        let bodyBytes = CosmosStakingHelper.buildTxBodyMulti(msgsAny: msgsAny, memo: "")
        let authInfoBytes = CosmosStakingHelper.buildAuthInfo(
            pubKey: pubKey,
            sequence: sequence,
            gasLimit: gasLimit,
            feeDenom: entry.feeDenom,
            feeAmount: feeAmount,
            pubKeyTypeURL: pubKeyTypeURL
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
        // Defense in depth — UI also enforces this, but the resolver must
        // reject oversized batches even when called directly (e.g. tests,
        // scripted payloads).
        guard validators.count <= maxBatchWithdrawValidators else {
            throw Errors.tooManyValidatorsToClaim(
                max: maxBatchWithdrawValidators,
                actual: validators.count
            )
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
