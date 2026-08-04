//
//  KaminoInstructionSequence.swift
//  VultisigApp
//

import Foundation

/// The instruction shapes each Kamino operation produces, and the walk that
/// matches a transaction against them.
///
/// Shared by the two places that need it, for the reason that matters: they must
/// agree on what a Kamino transaction is *allowed to contain*.
///
/// - `KaminoTransactionValidator` runs it on the initiating device, before
///   simulation and before signing, and follows it with account-identity checks
///   that need the address lookup tables resolved from the RPC.
/// - `KaminoTransactionDecoder` runs it on ANY device, offline, before claiming
///   to describe a transaction. Without it the decode would read one recognised
///   instruction and say nothing about the rest — so a transfer riding alongside
///   a plausible deposit would be summarised as "Deposit 1 USDC", which is a
///   worse outcome than showing nothing at all.
///
/// What a step matches on is deliberately only the program and the instruction
/// discriminator. Both are readable without a lookup table (a v0 message's
/// program ids are always static keys), which is what lets the offline decode
/// use the same template as the online validator. Everything else about an
/// instruction is checked after it has been matched, so a wrong ACCOUNT is a
/// refusal rather than a silent failure to match.
enum KaminoInstructionSequence {

    enum Kind {
        case computeUnitLimit
        case computeUnitPrice
        case createTokenAccount
        case wrapSolTransfer
        case syncNative
        case closeTokenAccount
        case kvaultDeposit
        case kvaultWithdraw
        case farmsInitializeUser
        case farmsStake

        var name: String {
            switch self {
            case .computeUnitLimit: return "compute unit limit"
            case .computeUnitPrice: return "compute unit price"
            case .createTokenAccount: return "create associated token account"
            case .wrapSolTransfer: return "SOL wrap transfer"
            case .syncNative: return "wrapped SOL sync"
            case .closeTokenAccount: return "close token account"
            case .kvaultDeposit: return "vault deposit"
            case .kvaultWithdraw: return "vault withdraw"
            case .farmsInitializeUser: return "farm user initialization"
            case .farmsStake: return "farm stake"
            }
        }
    }

    struct Step {
        let kind: Kind
        let isRequired: Bool
        let isRepeatable: Bool

        init(_ kind: Kind, required: Bool, repeatable: Bool) {
            self.kind = kind
            self.isRequired = required
            self.isRepeatable = repeatable
        }
    }

    /// Why a transaction does not fit the template.
    ///
    /// `Error` so it can travel in a `Result`; the validator translates it into
    /// a `KaminoValidationError` and the decoder only asks whether it happened.
    enum MatchFailure: Error, Equatable {
        /// An instruction the template does not name, at this position.
        case unexpectedInstruction(index: Int)
        /// A required step the transaction does not have.
        case missingInstruction(String)
    }

    /// The shape `operation` produces against a vault with these properties,
    /// verified by decoding transactions the Kamino API built and simulating
    /// them on mainnet.
    ///
    /// Optional steps are the ones whose absence cannot cost the user anything —
    /// an idempotent account creation that was already done, a farm user that
    /// already exists, a token account that stays open. Everything that decides
    /// where money moves is required, and anything not listed at all is refused.
    ///
    /// The withdraw sequence is the one that is not yet complete — see the
    /// extension point marked inside the `.withdraw` case below.
    ///
    /// - Parameter hasPriorityFee: whether the app's ComputeBudget pair has been
    ///   injected. The API emits none, so before injection their presence is a
    ///   refusal and after it their absence is.
    static func expected(
        operation: KaminoKeysignPayload.Operation,
        isWrappedSolVault: Bool,
        hasFarm: Bool,
        hasPriorityFee: Bool
    ) -> [Step] {
        var steps: [Step] = []
        if hasPriorityFee {
            steps.append(Step(.computeUnitLimit, required: true, repeatable: false))
            steps.append(Step(.computeUnitPrice, required: true, repeatable: false))
        }

        switch operation {
        case .deposit:
            steps.append(Step(.createTokenAccount, required: false, repeatable: true))
            if isWrappedSolVault {
                steps.append(Step(.wrapSolTransfer, required: true, repeatable: false))
                steps.append(Step(.syncNative, required: true, repeatable: false))
                steps.append(Step(.createTokenAccount, required: false, repeatable: true))
            }
            steps.append(Step(.kvaultDeposit, required: true, repeatable: false))
            if hasFarm {
                // Only the user's farm state may already exist. The stake itself
                // is what makes the shares the position the app then reads, so a
                // deposit that omits it is not the deposit that was requested.
                steps.append(Step(.farmsInitializeUser, required: false, repeatable: false))
                steps.append(Step(.farmsStake, required: true, repeatable: false))
            }

        case .withdraw:
            // EXTENSION POINT — the farm-staked withdraw.
            //
            // Every withdraw ever observed spent UNSTAKED shares, while every
            // deposit auto-stakes into the vault's farm. So the sequence below
            // is the only one that has been seen, and it is not the one the
            // users of these vaults are in: a withdraw of staked shares must
            // unstake them first, and neither the instruction it uses nor its
            // position in this list is known.
            //
            // A transaction carrying that unstake is therefore refused here as
            // an instruction the template does not name. That is deliberate. A
            // guessed step would validate the very shape it was guessed from and
            // assert nothing, which is worse than refusing.
            //
            // Completing it is a single edit, and it needs exactly three things,
            // all of which come from decoding ONE real mainnet withdraw of a
            // farm-staked position:
            //
            //   1. a `Kind` case for the unstake (its program is `farms`, its
            //      discriminator `sha256("global:<name>")[0..<8]`, added to
            //      `KaminoInstructionDiscriminator` and to `kind(program:data:)`);
            //   2. its account layout — at minimum the owner, the farm and the
            //      user's share account — added to `KaminoInstructionAccounts`
            //      and checked in `KaminoTransactionValidator.validateInstruction`
            //      the way `validateFarmsStake` checks the deposit's;
            //   3. the step inserted at its observed position below, `required`
            //      when the shares being spent are staked.
            //
            // `KaminoWithdrawEligibility.farmStaked` is the form-level half of
            // the same gap and comes out at the same time.
            steps.append(Step(.createTokenAccount, required: false, repeatable: true))
            steps.append(Step(.kvaultWithdraw, required: true, repeatable: false))
            // Only on a full withdraw: the emptied token account is closed and
            // its rent returned. The sampled vector is partial and carries none,
            // so this is optional rather than required.
            steps.append(Step(.closeTokenAccount, required: false, repeatable: false))
        }

        return steps
    }

    /// The kind of instruction this program and payload are, or `nil` when it is
    /// none the template knows.
    ///
    /// Program and discriminator only — see the type's doc for why.
    static func kind(program: KaminoSolanaProgram?, data: [UInt8]) -> Kind? {
        guard let program else { return nil }
        switch program {
        case .computeBudget:
            if data.first == ComputeBudgetInstruction.setUnitLimit { return .computeUnitLimit }
            if data.first == ComputeBudgetInstruction.setUnitPrice { return .computeUnitPrice }
            return nil
        case .associatedToken:
            return data.first == KaminoInstructionDiscriminator.createIdempotentAssociatedTokenAccount
                ? .createTokenAccount
                : nil
        case .system:
            return Array(data.prefix(4)) == KaminoInstructionDiscriminator.systemTransfer
                ? .wrapSolTransfer
                : nil
        case .token, .token2022:
            if data == [KaminoInstructionDiscriminator.tokenSyncNative] { return .syncNative }
            if data == [KaminoInstructionDiscriminator.tokenCloseAccount] { return .closeTokenAccount }
            return nil
        case .kvault:
            if Array(data.prefix(8)) == KaminoInstructionDiscriminator.kvaultDeposit { return .kvaultDeposit }
            if Array(data.prefix(8)) == KaminoInstructionDiscriminator.kvaultWithdraw { return .kvaultWithdraw }
            return nil
        case .farms:
            if Array(data.prefix(8)) == KaminoInstructionDiscriminator.farmsInitializeUser {
                return .farmsInitializeUser
            }
            if Array(data.prefix(8)) == KaminoInstructionDiscriminator.farmsStake { return .farmsStake }
            return nil
        }
    }

    /// Walks `steps` and `kinds` together. A step that does not match is skipped
    /// only when it is optional; an instruction left over at the end has no place
    /// in this operation at all.
    ///
    /// - Parameter kinds: one entry per instruction, in order, `nil` for an
    ///   instruction whose program is not allow-listed or whose discriminator is
    ///   not one the template names.
    /// - Returns: the step kind matched at each position, or the failure.
    static func match(kinds: [Kind?], against steps: [Step]) -> Result<[Kind], MatchFailure> {
        var matched: [Kind] = []
        var cursor = 0

        func matches(_ kind: Kind, at position: Int) -> Bool {
            guard kinds.indices.contains(position), let actual = kinds[position] else { return false }
            return actual == kind
        }

        for step in steps {
            if step.isRepeatable {
                while cursor < kinds.count, matches(step.kind, at: cursor) {
                    matched.append(step.kind)
                    cursor += 1
                }
                continue
            }
            if cursor < kinds.count, matches(step.kind, at: cursor) {
                matched.append(step.kind)
                cursor += 1
            } else if step.isRequired {
                return .failure(.missingInstruction(step.kind.name))
            }
        }

        guard cursor == kinds.count else {
            return .failure(.unexpectedInstruction(index: cursor))
        }
        return .success(matched)
    }
}

extension KaminoInstructionSequence.Kind: Equatable {}
