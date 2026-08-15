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
        case farmsUnstake
        case farmsWithdrawUnstakedDeposits
        case attributionMemo

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
            case .farmsUnstake: return "farm unstake"
            case .farmsWithdrawUnstakedDeposits: return "farm unstaked share withdrawal"
            case .attributionMemo: return "attribution memo"
            }
        }
    }

    struct Step {
        let kind: Kind
        let isRequired: Bool
        let isRepeatable: Bool
        /// A step this one may only appear alongside: either both are matched or
        /// neither is.
        ///
        /// Optionality is per-step, and for two instructions that are halves of
        /// ONE operation that is not enough. `farms::unstake` releases shares
        /// into a pending-withdrawal balance and
        /// `farms::withdraw_unstaked_deposits` is what moves them out of it —
        /// so an unstake on its own is not a smaller version of the pair, it is
        /// a transaction that takes shares out of the farm and strands them
        /// somewhere neither the position read nor the verify screen describes.
        /// Marking them optional individually would accept exactly that.
        let pairedWith: Kind?

        init(_ kind: Kind, required: Bool, repeatable: Bool, pairedWith: Kind? = nil) {
            self.kind = kind
            self.isRequired = required
            self.isRepeatable = repeatable
            self.pairedWith = pairedWith
        }
    }

    /// Whether a withdraw is supposed to release shares from the vault's farm.
    ///
    /// The API decides this from the user's position: a request that fits inside
    /// the shares already sitting in their share account is built as a plain
    /// two-instruction withdraw, and anything above it is built with the farms
    /// pair in front. Both shapes were captured — see the sequence tests — and
    /// they are genuinely different transactions, so which one is expected is an
    /// input to the template rather than something read out of the bytes.
    ///
    /// The three cases are three different claims, and the difference matters:
    ///
    /// - `.required` — the initiating device, which read the position and sized
    ///   the request against it. A transaction missing the unstake is refused.
    /// - `.forbidden` — the same device, for a request that fits the unstaked
    ///   balance. A transaction CARRYING an unstake is refused, because the
    ///   template does not name it and an unnamed instruction is a refusal.
    /// - `.unknown` — the offline decode on a co-signer, which holds no position
    ///   to compare against. Either shape is accepted, and what bounds it there
    ///   is the argument check: the unstake amount may not exceed the shares the
    ///   withdraw itself burns.
    enum FarmUnstake: Equatable {
        case required
        case forbidden
        case unknown

        var mayAppear: Bool { self != .forbidden }
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
        /// One half of a paired operation, without the other half.
        case incompleteInstructionPair(String)
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
    /// - Parameter hasPriorityFee: whether the app's ComputeBudget pair has been
    ///   injected. The API emits none, so before injection their presence is a
    ///   refusal and after it their absence is.
    /// - Parameter hasAttributionMemo: whether the app's attribution memo has
    ///   been appended. Same contract as `hasPriorityFee`, and for the same
    ///   reason: the API emits no memo, so one arriving before injection came
    ///   from somewhere else, and one missing after injection means the tag this
    ///   app claims to write is not in the bytes it is about to sign.
    /// - Parameter farmUnstake: whether this withdraw has to release shares from
    ///   the vault's farm first. Ignored for a deposit.
    static func expected(
        operation: KaminoKeysignPayload.Operation,
        isWrappedSolVault: Bool,
        hasFarm: Bool,
        hasPriorityFee: Bool,
        hasAttributionMemo: Bool = false,
        farmUnstake: FarmUnstake = .unknown
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
            // The share account the released shares land in, created first
            // because the two farms instructions below need it to exist.
            steps.append(Step(.createTokenAccount, required: false, repeatable: true))
            if hasFarm, farmUnstake.mayAppear {
                // BOTH farms instructions, and both BEFORE the vault withdraw —
                // the shares have to be out of the farm and in the user's own
                // account before anything can burn them. `unstake` releases
                // them; `withdraw_unstaked_deposits` moves them.
                //
                // They appear together or not at all: the API emits neither when
                // the request fits inside the shares the user already holds
                // unstaked, and both when it does not. `farmUnstake` is what
                // decides which of those two this transaction is supposed to be,
                // so a caller that knows gets a REQUIRED pair and a caller that
                // cannot know gets an optional one — never a silent "either is
                // fine" for the device that could have checked.
                let required = farmUnstake == .required
                steps.append(
                    Step(
                        .farmsUnstake,
                        required: required,
                        repeatable: false,
                        pairedWith: .farmsWithdrawUnstakedDeposits
                    )
                )
                steps.append(
                    Step(
                        .farmsWithdrawUnstakedDeposits,
                        required: required,
                        repeatable: false,
                        pairedWith: .farmsUnstake
                    )
                )
                // The payout account, created after the unstake rather than
                // alongside the first creation. Two `createIdempotent`s, not one.
                steps.append(Step(.createTokenAccount, required: false, repeatable: true))
            }
            steps.append(Step(.kvaultWithdraw, required: true, repeatable: false))
            // Emptied token accounts, closed so their rent comes back.
            //
            // REPEATABLE, because a full wrapped-SOL withdraw carries TWO: the
            // payout account and the now-empty share account. A captured
            // mainnet transaction does exactly that, and a template allowing
            // only one would have refused it.
            //
            // REQUIRED on the wrapped-SOL vault, because there closing the
            // payout account is not housekeeping — it is what unwraps wSOL into
            // the native SOL the form and the payload both say the user
            // receives. A withdraw without it executes and leaves wrapped SOL in
            // a token account while the screen promises SOL. Every wrapped-SOL
            // withdraw sampled carries one, staked and unstaked, partial and
            // full.
            //
            // Optional elsewhere: on the USDC vaults it appears only on a full
            // withdraw of an unstaked position, and not at all on the
            // farm-staked path — so its absence there is not a finding.
            steps.append(Step(.closeTokenAccount, required: isWrappedSolVault, repeatable: true))
        }

        // Last, because that is where the injector appends it: the memo records
        // who originated the transaction and takes no part in what it does, so
        // it sits behind every instruction that moves money rather than in
        // front of them.
        if hasAttributionMemo {
            steps.append(Step(.attributionMemo, required: true, repeatable: false))
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
        case .memo:
            // The tag is matched WHOLE, not as a prefix. A memo is free-form
            // bytes, so the tag followed by anything else is a different memo —
            // and the one thing this app is willing to sign under the Memo
            // program is its own attribution tag, exactly.
            return data == KaminoAttribution.memoTagBytes ? .attributionMemo : nil

        case .farms:
            if Array(data.prefix(8)) == KaminoInstructionDiscriminator.farmsInitializeUser {
                return .farmsInitializeUser
            }
            if Array(data.prefix(8)) == KaminoInstructionDiscriminator.farmsStake { return .farmsStake }
            if Array(data.prefix(8)) == KaminoInstructionDiscriminator.farmsUnstake { return .farmsUnstake }
            if Array(data.prefix(8)) == KaminoInstructionDiscriminator.farmsWithdrawUnstakedDeposits {
                return .farmsWithdrawUnstakedDeposits
            }
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
                // A repeatable step consumes as many as it finds — and if it is
                // also REQUIRED it has to find at least one. Skipping that check
                // because the loop already ran is how "one or more" silently
                // becomes "zero or more": the wrapped-SOL withdraw's close is
                // both, and without this its requirement would not exist.
                var consumed = 0
                while cursor < kinds.count, matches(step.kind, at: cursor) {
                    matched.append(step.kind)
                    cursor += 1
                    consumed += 1
                }
                if step.isRequired, consumed == 0 {
                    return .failure(.missingInstruction(step.kind.name))
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

        // Paired steps, last: a half-operation is a refusal even when both of
        // its halves were individually optional. This is what an OPTIONAL farms
        // pair means — either the transaction releases shares from the farm and
        // moves them, or it does neither.
        for step in steps {
            guard let companion = step.pairedWith else { continue }
            guard matched.contains(step.kind) == matched.contains(companion) else {
                return .failure(.incompleteInstructionPair(step.kind.name))
            }
        }
        return .success(matched)
    }
}

extension KaminoInstructionSequence.Kind: Equatable {}
