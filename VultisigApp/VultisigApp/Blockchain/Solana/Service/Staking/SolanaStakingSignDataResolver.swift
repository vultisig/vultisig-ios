//
//  SolanaStakingSignDataResolver.swift
//  VultisigApp
//
//  Produces the `SignSolana` artefact for a Solana native-staking operation.
//  Consumed by the Verify → KeysignPayload bridge whenever
//  `SendTransaction.solanaStakingPayload != nil`. Analog of
//  `CosmosStakingSignDataResolver`.
//
//  Unlike the transfer path — where every co-signing device rebuilds the
//  signing input from fields that all round-trip through proto — a delegate's
//  validator pubkey + amount live on the LOCAL-ONLY `solanaStakingPayload`,
//  which the peer never receives. So the resolver builds the unsigned
//  transaction ONCE here (pinning the recent blockhash and the
//  wallet-core-derived stake-account address) and relays the raw bytes via
//  `SignSolana.rawTransactions`. Every device then signs the byte-identical
//  message through the raw-transaction path — the MPC byte-parity guarantee.
//
//  Validator preflight (base58 ed25519 + optional known-vote-set membership)
//  is enforced HERE, before any pre-image bytes are produced, so an invalid
//  validator throws at build time rather than burning an MPC ceremony on a
//  chain-rejected tx.
//

import Foundation
import OSLog

enum SolanaStakingSignDataResolver {

    enum Errors: Error, LocalizedError {
        case missingPayload
        case wrongOpType(SolanaStakingOpType)
        case wrongMoveStakeStep(SolanaMoveStakeStep?)
        case missingChainSpecific
        case missingPayloadField(String)
        case validatorPreflightFailed(String)
        case insufficientForRentReserve(required: UInt64, available: UInt64)
        case partialSplitUnsupported

        var errorDescription: String? {
            switch self {
            case .missingPayload:
                return "solanaStakingErrorMissingPayload".localized
            case .wrongOpType:
                return "solanaStakingErrorWrongOpType".localized
            case .wrongMoveStakeStep:
                return "solanaStakingErrorWrongOpType".localized
            case .missingChainSpecific:
                return "solanaStakingErrorMissingChainSpecific".localized
            case .missingPayloadField(let field):
                return String(format: "solanaStakingErrorMissingPayloadField".localized, field)
            case .validatorPreflightFailed(let reason):
                return String(format: "solanaStakingErrorValidatorPreflightFailed".localized, reason)
            case .insufficientForRentReserve:
                return "solanaStakingErrorInsufficientForRentReserve".localized
            case .partialSplitUnsupported:
                return "solanaStakingErrorPartialSplitUnsupported".localized
            }
        }
    }

    private static let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "solana-staking-sign-resolver"
    )

    /// Resolves the `SignSolana` artefact for a delegate payload.
    ///
    /// - Parameters:
    ///   - basePayload: the transfer-shaped payload produced by the keysign
    ///     factory, already carrying `coin` / `chainSpecific` / `solanaStakingPayload`.
    ///   - rentReserve: the rent-exempt reserve (lamports) from the live read
    ///     layer (`getMinimumBalanceForRentExemption`). The new stake account must
    ///     be funded with this on top of the delegated amount.
    ///   - knownVotePubkeys: cached `getVoteAccounts` vote pubkeys for the
    ///     membership preflight; empty skips the membership check.
    ///   - balance: the signer's spendable lamports, used for the rent-reserve
    ///     accounting guard.
    static func resolve(
        basePayload: KeysignPayload,
        rentReserve: UInt64,
        knownVotePubkeys: Set<String>,
        balance: UInt64
    ) throws -> SignSolana {
        guard let payload = basePayload.solanaStakingPayload else {
            throw Errors.missingPayload
        }
        guard payload.opType == .delegate else {
            throw Errors.wrongOpType(payload.opType)
        }
        guard case .Solana = basePayload.chainSpecific else {
            throw Errors.missingChainSpecific
        }
        guard let votePubkey = payload.votePubkey, !votePubkey.isEmpty else {
            throw Errors.missingPayloadField("votePubkey")
        }
        guard let lamports = payload.lamports, lamports > 0 else {
            throw Errors.missingPayloadField("lamports")
        }

        do {
            try SolanaValidatorPreflight.validate(votePubkey, knownVotePubkeys: knownVotePubkeys)
        } catch {
            throw Errors.validatorPreflightFailed(error.localizedDescription)
        }

        // Rent-reserve accounting: a new stake account must hold the delegated
        // amount AND the rent-exempt reserve. Both come from the signer's
        // balance, so reject up front when the balance can't cover both —
        // otherwise the ceremony signs a tx the chain rejects.
        let (required, overflow) = lamports.addingReportingOverflow(rentReserve)
        if overflow || required > balance {
            throw Errors.insufficientForRentReserve(required: overflow ? .max : required, available: balance)
        }

        let rawTransaction = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: basePayload)

        logger.info(
            """
            Built Solana delegate tx: lamports=\(lamports) rentReserve=\(rentReserve) \
            validator=\(votePubkey, privacy: .public)
            """
        )

        return SignSolana(rawTransactions: [rawTransaction])
    }

    /// Resolves the `SignSolana` artefact for a deactivate (unstake) payload.
    /// Unlike delegate there is no validator preflight or rent-reserve guard —
    /// deactivate operates on an existing stake account and carries no amount.
    /// The stake-account address round-trips through the payload, but byte
    /// parity still rides the relayed raw bytes so peer devices need no payload.
    static func resolveDeactivate(basePayload: KeysignPayload) throws -> SignSolana {
        guard let payload = basePayload.solanaStakingPayload else {
            throw Errors.missingPayload
        }
        guard payload.opType == .unstake else {
            throw Errors.wrongOpType(payload.opType)
        }
        guard case .Solana = basePayload.chainSpecific else {
            throw Errors.missingChainSpecific
        }
        guard let stakeAccount = payload.stakeAccount, !stakeAccount.isEmpty else {
            throw Errors.missingPayloadField("stakeAccount")
        }

        let rawTransaction = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: basePayload)

        logger.info("Built Solana deactivate tx: stakeAccount=\(stakeAccount, privacy: .public)")

        return SignSolana(rawTransactions: [rawTransaction])
    }

    /// Resolves the `SignSolana` artefact for a withdraw payload. The withdraw
    /// CTA is gated upstream by `SolanaEpochCooldownGate` (full inactivity), so
    /// no cooldown check is repeated here — only the field/shape validation and
    /// the byte-parity build. Carries the stake account + the withdrawal amount.
    static func resolveWithdraw(basePayload: KeysignPayload) throws -> SignSolana {
        guard let payload = basePayload.solanaStakingPayload else {
            throw Errors.missingPayload
        }
        guard payload.opType == .withdraw else {
            throw Errors.wrongOpType(payload.opType)
        }
        guard case .Solana = basePayload.chainSpecific else {
            throw Errors.missingChainSpecific
        }
        guard let stakeAccount = payload.stakeAccount, !stakeAccount.isEmpty else {
            throw Errors.missingPayloadField("stakeAccount")
        }
        guard let lamports = payload.lamports, lamports > 0 else {
            throw Errors.missingPayloadField("lamports")
        }

        let rawTransaction = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: basePayload)

        logger.info(
            """
            Built Solana withdraw tx: stakeAccount=\(stakeAccount, privacy: .public) \
            lamports=\(lamports)
            """
        )

        return SignSolana(rawTransactions: [rawTransaction])
    }

    /// Resolves the `SignSolana` artefact for one guided move-stake sub-step.
    /// Each sub-step is signed and broadcast independently across epochs:
    ///
    ///   - `.deactivate`: byte-identical to a plain deactivate on the moved
    ///     account — no amount, no validator preflight.
    ///   - `.redelegate`: a delegate targeting the existing cooled-down account,
    ///     so it carries the validator preflight and re-uses the relayed-bytes
    ///     parity contract.
    ///   - `.split`: a partial move needs a Stake-program Split instruction
    ///     wallet-core does not expose — rejected here so the user moves the
    ///     whole account instead.
    static func resolveMoveStake(basePayload: KeysignPayload, knownVotePubkeys: Set<String>) throws -> SignSolana {
        guard let payload = basePayload.solanaStakingPayload else {
            throw Errors.missingPayload
        }
        guard payload.opType == .moveStakeStep else {
            throw Errors.wrongOpType(payload.opType)
        }
        guard case .Solana = basePayload.chainSpecific else {
            throw Errors.missingChainSpecific
        }

        switch payload.moveStakeSubStep {
        case .deactivate:
            return try resolveMoveStakeDeactivate(payload: payload, basePayload: basePayload)
        case .redelegate:
            return try resolveMoveStakeRedelegate(
                payload: payload,
                basePayload: basePayload,
                knownVotePubkeys: knownVotePubkeys
            )
        case .split:
            throw Errors.partialSplitUnsupported
        case .none:
            throw Errors.wrongMoveStakeStep(nil)
        }
    }

    private static func resolveMoveStakeDeactivate(
        payload: SolanaStakingPayload,
        basePayload: KeysignPayload
    ) throws -> SignSolana {
        guard let stakeAccount = payload.stakeAccount, !stakeAccount.isEmpty else {
            throw Errors.missingPayloadField("stakeAccount")
        }

        let rawTransaction = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: basePayload)

        logger.info("Built Solana move-stake deactivate tx: stakeAccount=\(stakeAccount, privacy: .public)")

        return SignSolana(rawTransactions: [rawTransaction])
    }

    private static func resolveMoveStakeRedelegate(
        payload: SolanaStakingPayload,
        basePayload: KeysignPayload,
        knownVotePubkeys: Set<String>
    ) throws -> SignSolana {
        guard let stakeAccount = payload.stakeAccount, !stakeAccount.isEmpty else {
            throw Errors.missingPayloadField("stakeAccount")
        }
        guard let votePubkey = payload.votePubkey, !votePubkey.isEmpty else {
            throw Errors.missingPayloadField("votePubkey")
        }
        guard let lamports = payload.lamports, lamports > 0 else {
            throw Errors.missingPayloadField("lamports")
        }

        do {
            try SolanaValidatorPreflight.validate(votePubkey, knownVotePubkeys: knownVotePubkeys)
        } catch {
            throw Errors.validatorPreflightFailed(error.localizedDescription)
        }

        let rawTransaction = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: basePayload)

        logger.info(
            """
            Built Solana move-stake redelegate tx: stakeAccount=\(stakeAccount, privacy: .public) \
            validator=\(votePubkey, privacy: .public) lamports=\(lamports)
            """
        )

        return SignSolana(rawTransactions: [rawTransaction])
    }
}
