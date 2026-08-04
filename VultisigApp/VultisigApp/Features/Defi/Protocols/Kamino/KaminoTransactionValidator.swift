//
//  KaminoTransactionValidator.swift
//  VultisigApp
//

import BigInt
import Foundation
import OSLog

private let logger = Log.defi.other

/// What the user asked for. The amount carries its unit in its type, so the
/// deposit/withdraw asymmetry — token base units one way, SHARE base units the
/// other — cannot be confused at the point where it is checked against the bytes.
enum KaminoOperation {
    case deposit(KaminoTokenAmount)
    case withdraw(KaminoShareAmount)
}

/// The priority fee the app injected: a compute unit limit and a price per unit.
///
/// The fee the network charges is `limit × price`, paid in SOL by the fee payer,
/// so both halves are a spend and both are checked against the values the app
/// chose rather than accepted from the transaction.
struct KaminoPriorityFee: Equatable {
    let limit: UInt32
    /// Micro-lamports per compute unit.
    let price: UInt64
}

/// The request a built transaction is supposed to be the answer to.
struct KaminoTransactionIntent {
    let operation: KaminoOperation
    let vault: KaminoVaultInfo
    /// The user's Solana address: fee payer, sole signer, and the account every
    /// destination must belong to.
    let owner: String
    /// The priority fee the app injected, or `nil` before injection — in which
    /// case any ComputeBudget instruction at all is a refusal, because Kamino's
    /// builder emits none and a fee we did not choose is SOL leaving the wallet.
    let priorityFee: KaminoPriorityFee?

    init(
        operation: KaminoOperation,
        vault: KaminoVaultInfo,
        owner: String,
        priorityFee: KaminoPriorityFee? = nil
    ) {
        self.operation = operation
        self.vault = vault
        self.owner = owner
        self.priorityFee = priorityFee
    }
}

enum KaminoValidationError: Error, LocalizedError, Equatable {
    case vaultNotAllowed(String)
    /// The vault carries an allow-listed address but describes itself
    /// differently from the registry entry for that address.
    case vaultDescriptorMismatch(String)
    case unexpectedLookupTable(expected: String, actual: String)
    case tooManyLookupTables(Int)
    case accountResolutionMismatch(resolved: Int, expected: Int)
    case programNotAllowed(instruction: Int, program: String)
    case unexpectedInstruction(index: Int, program: String)
    /// An instruction that is well formed but belongs to the other operation, or
    /// to a vault configuration this one does not have.
    case instructionNotForOperation(index: Int, detail: String)
    case missingInstruction(String)
    case malformedInstruction(index: Int, detail: String)
    case accountMismatch(role: String, expected: String, actual: String)
    case accountNotOwnedByUser(role: String, actual: String)
    case amountMismatch(role: String, expected: String, actual: String)
    case amountOutOfRange(String)
    case unexpectedPriorityFee(index: Int)
    case unattributableWritableAccount(program: String, account: String)
    case unreferencedWritableAccount(String)
    case addressDerivationFailed(String)

    var errorDescription: String? {
        switch self {
        case .vaultNotAllowed(let address):
            return "Vault \(address) is not one this app transacts with"
        case .vaultDescriptorMismatch(let address):
            return "Vault \(address) does not match this app's record of it"
        case .unexpectedLookupTable(let expected, let actual):
            return "Transaction uses address lookup table \(actual); the vault's is \(expected)"
        case .tooManyLookupTables(let count):
            return "Transaction uses \(count) address lookup tables; at most one is expected"
        case .accountResolutionMismatch(let resolved, let expected):
            return "Resolved \(resolved) accounts for a transaction addressing \(expected)"
        case .programNotAllowed(let index, let program):
            return "Instruction \(index) invokes \(program), which is not an allowed program"
        case .unexpectedInstruction(let index, let program):
            return "Instruction \(index) (\(program)) is not part of this operation"
        case .instructionNotForOperation(let index, let detail):
            return "Instruction \(index) is a \(detail) instruction, which this operation does not perform"
        case .missingInstruction(let name):
            return "Transaction is missing its \(name) instruction"
        case .malformedInstruction(let index, let detail):
            return "Instruction \(index) is malformed: \(detail)"
        case .accountMismatch(let role, let expected, let actual):
            return "Transaction's \(role) is \(actual), expected \(expected)"
        case .accountNotOwnedByUser(let role, let actual):
            return "Transaction's \(role) is \(actual), which is not an account of yours"
        case .amountMismatch(let role, let expected, let actual):
            return "Transaction's \(role) is \(actual), expected \(expected)"
        case .amountOutOfRange(let detail):
            return "Amount cannot be expressed on chain: \(detail)"
        case .unexpectedPriorityFee(let index):
            return "Instruction \(index) sets a priority fee this app did not choose"
        case .unattributableWritableAccount(let program, let account):
            return "Instruction from \(program) writes to \(account), which this operation does not explain"
        case .unreferencedWritableAccount(let account):
            return "Transaction loads \(account) as writable but no instruction uses it"
        case .addressDerivationFailed(let detail):
            return "Could not derive \(detail)"
        }
    }
}

/// Fail-closed validation of a Kamino-built Solana transaction, in the
/// `SwapRecipientVerifier` mould.
///
/// Kamino builds the transaction, the app signs the bytes verbatim, and Blockaid
/// is advisory. So between an API response and a signature over it there is only
/// this. It runs before simulation and before keysign, and every finding is a
/// refusal — nothing here downgrades to a warning.
///
/// What it establishes, in layers:
///
/// 1. **Shape.** One required signature, still an unsigned placeholder, paid for
///    by the user. Every lookup table is the vault's own, so no account can be
///    named through a table we did not expect.
/// 2. **Programs.** Every `programIdIndex` resolves to an allow-listed program.
///    That is the outer bound on what the user's signature can authorise.
/// 3. **Sequence.** The instruction list must match the shape this operation
///    produces, in order. An instruction that is not in the template is a refusal
///    rather than something skipped — so a new one fails closed.
/// 4. **Identity.** Inside each instruction, the accounts that decide where money
///    goes are compared against values the app already had: the vault, its mints
///    and its farm come from the registry, and the user's token accounts from the
///    ATA derivation. None of them is read from the response — checking a
///    transaction the API built against metadata the same API supplied would be
///    circular, and a compromised response could make the pair agree.
/// 5. **Amount.** The `u64` the kvault instruction carries equals the amount the
///    user was shown — in tokens for a deposit, in shares for a withdraw. The
///    priority fee is an amount too: `limit × price` is SOL, so both halves must
///    equal the values the app injected, and before injection a ComputeBudget
///    instruction may not be there at all.
/// 6. **Writable accounts.** Every writable account is used by some instruction,
///    and any account a *builder-composed* instruction can write to must be one
///    of the accounts this operation explains. This is the layer that catches a
///    drain hidden in an otherwise plausible transaction.
///
/// What it does not establish is what the `kvault` and `farms` programs do with
/// the accounts they are handed. That is the protocol, and choosing to trust it
/// is what the registry allow-list expresses.
struct KaminoTransactionValidator {

    private let lookupTableSource: SolanaAddressLookupTableFetching

    init(lookupTableSource: SolanaAddressLookupTableFetching = SolanaService.shared) {
        self.lookupTableSource = lookupTableSource
    }

    /// Resolves the transaction's address lookup tables from the RPC, then
    /// validates it against `intent`.
    func validate(transaction: SolanaV0Transaction, intent: KaminoTransactionIntent) async throws {
        let tables = try await lookupTableSource.fetchAddressLookupTables(
            addresses: transaction.addressTableLookups.map(\.tableAddress)
        )
        do {
            try Self.validate(transaction: transaction, intent: intent, lookupTables: tables)
        } catch {
            logger.error("[kamino-validate] refused: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Pure core, exposed so it can be driven against pinned lookup-table
    /// contents rather than the network.
    ///
    /// - Parameter lookupTables: table address to that table's full address list.
    static func validate(
        transaction: SolanaV0Transaction,
        intent: KaminoTransactionIntent,
        lookupTables: [String: [String]]
    ) throws {
        let vaultAddress = intent.vault.descriptor.address
        guard let registered = KaminoVaultRegistry.descriptor(for: vaultAddress) else {
            throw KaminoValidationError.vaultNotAllowed(vaultAddress)
        }
        // Not just the address. Every value the checks below rest on — the mints,
        // their decimals, the farm — lives on this descriptor, so accepting one
        // that merely *claims* an allow-listed address would hand an attacker the
        // pinning itself. Comparing the whole descriptor makes the registry the
        // only possible source of a vault's identity, structurally rather than by
        // convention.
        guard registered == intent.vault.descriptor else {
            throw KaminoValidationError.vaultDescriptorMismatch(vaultAddress)
        }

        try transaction.validateUnsignedSingleSigner(feePayer: intent.owner)
        try validateLookupTables(transaction: transaction, expected: intent.vault.lookupTable)

        let accounts = try transaction.resolvedAccountAddresses(lookupTables: lookupTables)
        guard accounts.count == transaction.totalAccountCount else {
            throw KaminoValidationError.accountResolutionMismatch(
                resolved: accounts.count,
                expected: transaction.totalAccountCount
            )
        }

        let context = try Context(intent: intent, accounts: accounts, transaction: transaction)
        try validatePrograms(context)
        try validatePriorityFeePresence(context)
        try validateSequence(context)
        try validateWritableAccounts(context)
    }

    // MARK: - Lookup tables

    /// Every table the transaction reads from must be the vault's own.
    ///
    /// A table decides which pubkey an account index names, so a foreign one is
    /// how an account substitution would be hidden. Zero tables is allowed — then
    /// every account is a static key and there is nothing to hide behind.
    private static func validateLookupTables(transaction: SolanaV0Transaction, expected: String) throws {
        guard transaction.addressTableLookups.count <= 1 else {
            throw KaminoValidationError.tooManyLookupTables(transaction.addressTableLookups.count)
        }
        for lookup in transaction.addressTableLookups where lookup.tableAddress != expected {
            throw KaminoValidationError.unexpectedLookupTable(expected: expected, actual: lookup.tableAddress)
        }
    }

    // MARK: - Programs

    private static func validatePrograms(_ context: Context) throws {
        for (position, program) in context.programs.enumerated() where program == nil {
            throw KaminoValidationError.programNotAllowed(
                instruction: position,
                program: context.programId(at: position)
            )
        }
    }

    /// Before injection the app has chosen no fee, so a ComputeBudget
    /// instruction can only have come from the response.
    ///
    /// Checked separately from the sequence so the refusal names the real
    /// problem: a priority fee is `limit × price` lamports out of the user's
    /// balance, and an unrecognised one would otherwise read as a sequencing
    /// error.
    private static func validatePriorityFeePresence(_ context: Context) throws {
        guard context.intent.priorityFee == nil else { return }
        for (position, program) in context.programs.enumerated() where program == .computeBudget {
            throw KaminoValidationError.unexpectedPriorityFee(index: position)
        }
    }

    // MARK: - Instruction sequence

    /// Matches the transaction against the shape this operation produces, then
    /// runs each matched instruction's own account and amount checks.
    ///
    /// The template lives in `KaminoInstructionSequence` because the verify
    /// screen's offline decoder walks the same one: the two must agree on what a
    /// Kamino transaction may contain, or a transaction this validator would
    /// refuse could still be summarised to a co-signer as an ordinary deposit.
    private static func validateSequence(_ context: Context) throws {
        let steps = KaminoInstructionSequence.expected(
            operation: context.operation,
            isWrappedSolVault: context.intent.vault.isWrappedSolVault,
            hasFarm: context.intent.vault.hasFarm,
            hasPriorityFee: context.intent.priorityFee != nil
        )

        switch KaminoInstructionSequence.match(kinds: context.kinds, against: steps) {
        case .failure(.missingInstruction(let name)):
            throw KaminoValidationError.missingInstruction(name)
        case .failure(.unexpectedInstruction(let index)):
            throw KaminoValidationError.unexpectedInstruction(
                index: index,
                program: context.programId(at: index)
            )
        case .success(let matched):
            for (position, kind) in matched.enumerated() {
                try validateInstruction(kind, at: position, context)
            }
        }
    }

    // MARK: - Per-instruction checks

    private static func validateInstruction(
        _ kind: KaminoInstructionSequence.Kind,
        at position: Int,
        _ context: Context
    ) throws {
        let data = context.transaction.instructions[position].data
        let accounts = context.accountAddresses(at: position)

        switch kind {
        case .computeUnitLimit:
            try validateComputeUnitLimit(data: data, accounts: accounts, position: position, context)

        case .computeUnitPrice:
            try validateComputeUnitPrice(data: data, accounts: accounts, position: position, context)

        case .createTokenAccount:
            try validateCreateTokenAccount(accounts: accounts, position: position, context)

        case .wrapSolTransfer:
            try validateWrapSolTransfer(data: data, accounts: accounts, position: position, context)

        case .syncNative:
            guard let account = accounts.first else {
                throw KaminoValidationError.malformedInstruction(index: position, detail: "syncNative takes an account")
            }
            try context.requireUserTokenAccount(account, role: "wrapped SOL account")

        case .closeTokenAccount:
            try validateCloseTokenAccount(accounts: accounts, position: position, context)

        case .kvaultDeposit:
            try validateKvaultDeposit(data: data, accounts: accounts, position: position, context)

        case .kvaultWithdraw:
            try validateKvaultWithdraw(data: data, accounts: accounts, position: position, context)

        case .farmsInitializeUser:
            try validateFarmsInitializeUser(accounts: accounts, position: position, context)

        case .farmsStake:
            try validateFarmsStake(data: data, accounts: accounts, position: position, context)
        }
    }

    /// The compute unit limit, pinned to the value the app injected.
    ///
    /// A limit is half of the fee: the network charges `limit × price`, so a
    /// limit raised beyond what the transaction needs is SOL spent for nothing.
    private static func validateComputeUnitLimit(
        data: [UInt8],
        accounts: [String],
        position: Int,
        _ context: Context
    ) throws {
        try requireNoAccounts(accounts, position: position)
        guard let fee = context.intent.priorityFee,
              let limit = KaminoInstructionDiscriminator.computeUnitLimit(data) else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "compute unit limit")
        }
        guard limit == fee.limit else {
            throw KaminoValidationError.amountMismatch(
                role: "compute unit limit",
                expected: String(fee.limit),
                actual: String(limit)
            )
        }
    }

    /// The price per compute unit, pinned to the value the app injected. This is
    /// the half an attacker would inflate: it is a `u64` of micro-lamports and
    /// nothing on chain caps the resulting fee below the payer's balance.
    private static func validateComputeUnitPrice(
        data: [UInt8],
        accounts: [String],
        position: Int,
        _ context: Context
    ) throws {
        try requireNoAccounts(accounts, position: position)
        guard let fee = context.intent.priorityFee,
              let price = KaminoInstructionDiscriminator.computeUnitPrice(data) else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "compute unit price")
        }
        guard price == fee.price else {
            throw KaminoValidationError.amountMismatch(
                role: "compute unit price",
                expected: String(fee.price),
                actual: String(price)
            )
        }
    }

    private static func requireNoAccounts(_ accounts: [String], position: Int) throws {
        guard accounts.isEmpty else {
            throw KaminoValidationError.malformedInstruction(
                index: position,
                detail: "compute budget instructions take no accounts"
            )
        }
    }

    /// A `CreateIdempotent` may only create one of the vault's two mints'
    /// accounts, for the user, at the address that derivation says it must have.
    /// Creating an account is harmless in itself, but it is also where a
    /// third-party destination would first appear.
    private static func validateCreateTokenAccount(accounts: [String], position: Int, _ context: Context) throws {
        guard accounts.count >= KaminoInstructionAccounts.AssociatedToken.count else {
            throw KaminoValidationError.malformedInstruction(
                index: position,
                detail: "createIdempotent needs \(KaminoInstructionAccounts.AssociatedToken.count) accounts"
            )
        }
        try context.requireOwner(accounts[KaminoInstructionAccounts.AssociatedToken.payer], role: "token account funder")
        try context.requireOwner(accounts[KaminoInstructionAccounts.AssociatedToken.wallet], role: "token account owner")

        let mint = accounts[KaminoInstructionAccounts.AssociatedToken.mint]
        guard mint == context.intent.vault.tokenMint || mint == context.intent.vault.sharesMint else {
            throw KaminoValidationError.accountMismatch(
                role: "created token account mint",
                expected: "\(context.intent.vault.tokenMint) or \(context.intent.vault.sharesMint)",
                actual: mint
            )
        }

        let programId = accounts[KaminoInstructionAccounts.AssociatedToken.tokenProgram]
        guard let tokenProgram = SolanaTokenProgram(programId: programId) else {
            throw KaminoValidationError.programNotAllowed(instruction: position, program: programId)
        }
        guard let derived = SolanaAssociatedTokenAccount.derive(
            owner: context.intent.owner,
            mint: mint,
            tokenProgram: tokenProgram
        ) else {
            throw KaminoValidationError.addressDerivationFailed("the associated token account for \(mint)")
        }
        guard accounts[KaminoInstructionAccounts.AssociatedToken.account] == derived else {
            throw KaminoValidationError.accountMismatch(
                role: "created token account",
                expected: derived,
                actual: accounts[KaminoInstructionAccounts.AssociatedToken.account]
            )
        }
    }

    /// The lamports that fund the wSOL account. This is the only native SOL
    /// movement the operation performs, so both its endpoints and its amount are
    /// pinned: out of the user's own account, into the user's own wSOL account,
    /// for exactly the deposit.
    private static func validateWrapSolTransfer(
        data: [UInt8],
        accounts: [String],
        position: Int,
        _ context: Context
    ) throws {
        guard accounts.count >= KaminoInstructionAccounts.SystemTransfer.count,
              let lamports = KaminoInstructionDiscriminator.systemTransferLamports(data) else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "system transfer")
        }
        try context.requireOwner(accounts[KaminoInstructionAccounts.SystemTransfer.source], role: "SOL transfer source")
        try context.requireUserTokenAccount(
            accounts[KaminoInstructionAccounts.SystemTransfer.destination],
            role: "SOL transfer destination"
        )

        guard case .deposit(let amount) = context.intent.operation else {
            throw KaminoValidationError.instructionNotForOperation(index: position, detail: "SOL wrap")
        }
        let expected = try requireUInt64(amount.baseUnits, role: "deposit amount")
        guard lamports == expected else {
            throw KaminoValidationError.amountMismatch(
                role: "wrapped SOL amount",
                expected: String(expected),
                actual: String(lamports)
            )
        }
    }

    /// Closing a token account sends its remaining lamports somewhere. Both the
    /// account being closed and where its rent lands have to be the user's.
    private static func validateCloseTokenAccount(accounts: [String], position: Int, _ context: Context) throws {
        guard accounts.count >= KaminoInstructionAccounts.CloseAccount.count else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "closeAccount")
        }
        let closed = accounts[KaminoInstructionAccounts.CloseAccount.account]
        guard context.userTokenAccounts.contains(closed) || context.userShareAccounts.contains(closed) else {
            throw KaminoValidationError.accountNotOwnedByUser(role: "closed token account", actual: closed)
        }
        try context.requireOwner(accounts[KaminoInstructionAccounts.CloseAccount.destination], role: "closed account rent destination")
        try context.requireOwner(accounts[KaminoInstructionAccounts.CloseAccount.authority], role: "closed account authority")
    }

    private static func validateKvaultDeposit(
        data: [UInt8],
        accounts: [String],
        position: Int,
        _ context: Context
    ) throws {
        guard accounts.count >= KaminoInstructionAccounts.KvaultDeposit.minimumCount else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "kvault deposit accounts")
        }
        guard case .deposit(let amount) = context.intent.operation else {
            throw KaminoValidationError.instructionNotForOperation(index: position, detail: "vault deposit")
        }

        try context.requireOwner(accounts[KaminoInstructionAccounts.KvaultDeposit.user], role: "deposit authority")
        try context.requireVault(accounts[KaminoInstructionAccounts.KvaultDeposit.vault])
        try context.requireMint(accounts[KaminoInstructionAccounts.KvaultDeposit.tokenMint], expected: context.intent.vault.tokenMint, role: "deposit token mint")
        try context.requireMint(accounts[KaminoInstructionAccounts.KvaultDeposit.sharesMint], expected: context.intent.vault.sharesMint, role: "deposit shares mint")
        try context.requireUserTokenAccount(accounts[KaminoInstructionAccounts.KvaultDeposit.userTokenAccount], role: "deposit source")
        try context.requireUserShareAccount(accounts[KaminoInstructionAccounts.KvaultDeposit.userShareAccount], role: "deposit share destination")

        try requireAnchorAmount(
            data: data,
            position: position,
            expected: amount.baseUnits,
            role: "deposit amount"
        )
    }

    private static func validateKvaultWithdraw(
        data: [UInt8],
        accounts: [String],
        position: Int,
        _ context: Context
    ) throws {
        guard accounts.count >= KaminoInstructionAccounts.KvaultWithdraw.minimumCount else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "kvault withdraw accounts")
        }
        guard case .withdraw(let shares) = context.intent.operation else {
            throw KaminoValidationError.instructionNotForOperation(index: position, detail: "vault withdraw")
        }

        try context.requireOwner(accounts[KaminoInstructionAccounts.KvaultWithdraw.user], role: "withdraw authority")
        try context.requireVault(accounts[KaminoInstructionAccounts.KvaultWithdraw.vault])
        try context.requireMint(accounts[KaminoInstructionAccounts.KvaultWithdraw.tokenMint], expected: context.intent.vault.tokenMint, role: "withdraw token mint")
        try context.requireMint(accounts[KaminoInstructionAccounts.KvaultWithdraw.sharesMint], expected: context.intent.vault.sharesMint, role: "withdraw shares mint")
        try context.requireUserTokenAccount(accounts[KaminoInstructionAccounts.KvaultWithdraw.userTokenAccount], role: "withdraw destination")
        try context.requireUserShareAccount(accounts[KaminoInstructionAccounts.KvaultWithdraw.userShareAccount], role: "withdraw share source")

        // Shares, not tokens. The API takes the same `amount` field for both
        // actions with inverted units, and an amount above the user's balance is
        // silently rewritten to u64::MAX — withdraw everything — so this is the
        // check that stands between a partial exit and a full one.
        try requireAnchorAmount(
            data: data,
            position: position,
            expected: shares.baseUnits,
            role: "withdraw share amount"
        )
    }

    private static func validateFarmsInitializeUser(accounts: [String], position: Int, _ context: Context) throws {
        guard accounts.count >= KaminoInstructionAccounts.FarmsInitializeUser.minimumCount else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "farms initializeUser accounts")
        }
        try context.requireOwner(accounts[KaminoInstructionAccounts.FarmsInitializeUser.authority], role: "farm user authority")
        try context.requireFarm(accounts[KaminoInstructionAccounts.FarmsInitializeUser.farm], position: position)
    }

    /// The stake that makes the deposit's shares invisible in the wallet. It must
    /// move the user's own shares into this vault's own farm — a farm belonging
    /// to another vault would park the position somewhere the app never reads.
    private static func validateFarmsStake(
        data: [UInt8],
        accounts: [String],
        position: Int,
        _ context: Context
    ) throws {
        guard accounts.count >= KaminoInstructionAccounts.FarmsStake.minimumCount else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "farms stake accounts")
        }
        try context.requireOwner(accounts[KaminoInstructionAccounts.FarmsStake.owner], role: "stake authority")
        try context.requireFarm(accounts[KaminoInstructionAccounts.FarmsStake.farm], position: position)
        try context.requireUserShareAccount(accounts[KaminoInstructionAccounts.FarmsStake.userShareAccount], role: "stake source")
        try context.requireMint(accounts[KaminoInstructionAccounts.FarmsStake.sharesMint], expected: context.intent.vault.sharesMint, role: "stake shares mint")

        // Kamino stakes the whole share balance rather than the freshly minted
        // amount, so the argument is the u64 sentinel. A different value is a
        // behaviour change, not a variation, and is worth stopping on.
        guard let argument = KaminoInstructionDiscriminator.anchorArgument(data) else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "farms stake argument")
        }
        guard argument == UInt64.max else {
            throw KaminoValidationError.amountMismatch(
                role: "staked share amount",
                expected: String(UInt64.max),
                actual: String(argument)
            )
        }
    }

    // MARK: - Writable accounts

    /// Two rules, together covering "no unexplained writes".
    ///
    /// A writable account nothing references is a loaded write privilege with no
    /// purpose, which is not a shape any legitimate builder emits. And an account
    /// that a builder-composed instruction can write to has to be one this
    /// operation can name — the user, the vault, its two mints, or the user's own
    /// token accounts for them. A drain has to write somewhere, and outside the
    /// `kvault`/`farms` programs there is nowhere left for it to write.
    private static func validateWritableAccounts(_ context: Context) throws {
        var referenced = Set<Int>()
        for instruction in context.transaction.instructions {
            referenced.formUnion(instruction.accountIndexes.map(Int.init))
        }
        for index in context.accounts.indices
        where context.transaction.isWritable(accountIndex: index) && !referenced.contains(index) {
            throw KaminoValidationError.unreferencedWritableAccount(context.accounts[index])
        }

        for (position, program) in context.programs.enumerated() {
            guard let program, program.isBuilderComposed else { continue }
            for index in context.transaction.instructions[position].accountIndexes
            where context.transaction.isWritable(accountIndex: Int(index)) {
                let account = context.accounts[Int(index)]
                guard context.explainedAccounts.contains(account) else {
                    throw KaminoValidationError.unattributableWritableAccount(
                        program: program.rawValue,
                        account: account
                    )
                }
            }
        }
    }

    // MARK: - Amount helpers

    private static func requireAnchorAmount(
        data: [UInt8],
        position: Int,
        expected: BigInt,
        role: String
    ) throws {
        guard let argument = KaminoInstructionDiscriminator.anchorArgument(data) else {
            throw KaminoValidationError.malformedInstruction(index: position, detail: "\(role) argument")
        }
        let bounded = try requireUInt64(expected, role: role)
        guard argument == bounded else {
            throw KaminoValidationError.amountMismatch(
                role: role,
                expected: String(bounded),
                actual: String(argument)
            )
        }
    }

    private static func requireUInt64(_ value: BigInt, role: String) throws -> UInt64 {
        guard let bounded = UInt64(exactly: value) else {
            throw KaminoValidationError.amountOutOfRange("\(role) \(value)")
        }
        return bounded
    }
}

// MARK: - Context

private extension KaminoTransactionValidator {

    /// Everything the per-instruction checks compare against, resolved once.
    struct Context {
        let intent: KaminoTransactionIntent
        let transaction: SolanaV0Transaction
        /// Every account the message addresses, in index order.
        let accounts: [String]
        /// The program each instruction invokes, `nil` when it is not allow-listed.
        let programs: [KaminoSolanaProgram?]
        /// The template step each instruction looks like, from its program and
        /// discriminator alone. `nil` for anything the template does not name.
        let kinds: [KaminoInstructionSequence.Kind?]
        /// The user's associated token accounts for the vault's underlying token,
        /// one per token program.
        let userTokenAccounts: Set<String>
        /// The same for the vault's share mint.
        let userShareAccounts: Set<String>
        /// Every account this operation can name — the set a builder-composed
        /// instruction's writes must fall inside.
        let explainedAccounts: Set<String>

        init(intent: KaminoTransactionIntent, accounts: [String], transaction: SolanaV0Transaction) throws {
            self.intent = intent
            self.transaction = transaction
            self.accounts = accounts
            let programs = transaction.instructions.map {
                KaminoSolanaProgram(programId: accounts[Int($0.programIdIndex)])
            }
            self.programs = programs
            self.kinds = zip(programs, transaction.instructions).map { program, instruction in
                KaminoInstructionSequence.kind(program: program, data: instruction.data)
            }

            let owner = intent.owner
            let tokenAccounts = SolanaAssociatedTokenAccount.ownedAccounts(
                owner: owner,
                mint: intent.vault.tokenMint
            )
            let shareAccounts = SolanaAssociatedTokenAccount.ownedAccounts(
                owner: owner,
                mint: intent.vault.sharesMint
            )
            guard !tokenAccounts.isEmpty, !shareAccounts.isEmpty else {
                throw KaminoValidationError.addressDerivationFailed("the user's associated token accounts")
            }

            self.userTokenAccounts = tokenAccounts
            self.userShareAccounts = shareAccounts
            self.explainedAccounts = tokenAccounts
                .union(shareAccounts)
                .union([owner, intent.vault.descriptor.address, intent.vault.tokenMint, intent.vault.sharesMint])
        }

        var operation: KaminoKeysignPayload.Operation {
            switch intent.operation {
            case .deposit: return .deposit
            case .withdraw: return .withdraw
            }
        }

        func programId(at position: Int) -> String {
            guard transaction.instructions.indices.contains(position) else { return "unknown" }
            return accounts[Int(transaction.instructions[position].programIdIndex)]
        }

        func accountAddresses(at position: Int) -> [String] {
            transaction.instructions[position].accountIndexes.map { accounts[Int($0)] }
        }

        func requireOwner(_ account: String, role: String) throws {
            guard account == intent.owner else {
                throw KaminoValidationError.accountMismatch(role: role, expected: intent.owner, actual: account)
            }
        }

        func requireVault(_ account: String) throws {
            let expected = intent.vault.descriptor.address
            guard account == expected else {
                throw KaminoValidationError.accountMismatch(role: "vault", expected: expected, actual: account)
            }
        }

        func requireMint(_ account: String, expected: String, role: String) throws {
            guard account == expected else {
                throw KaminoValidationError.accountMismatch(role: role, expected: expected, actual: account)
            }
        }

        func requireFarm(_ account: String, position: Int) throws {
            guard let farm = intent.vault.farm else {
                throw KaminoValidationError.instructionNotForOperation(index: position, detail: "farm")
            }
            guard account == farm else {
                throw KaminoValidationError.accountMismatch(role: "farm", expected: farm, actual: account)
            }
        }

        func requireUserTokenAccount(_ account: String, role: String) throws {
            guard userTokenAccounts.contains(account) else {
                throw KaminoValidationError.accountNotOwnedByUser(role: role, actual: account)
            }
        }

        func requireUserShareAccount(_ account: String, role: String) throws {
            guard userShareAccounts.contains(account) else {
                throw KaminoValidationError.accountNotOwnedByUser(role: role, actual: account)
            }
        }
    }
}
