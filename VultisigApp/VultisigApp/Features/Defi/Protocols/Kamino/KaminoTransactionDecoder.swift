//
//  KaminoTransactionDecoder.swift
//  VultisigApp
//

import BigInt
import Foundation
import WalletCore

/// What a Kamino transaction does, read back out of the bytes that will be
/// signed.
///
/// Every field is derived from the wire message plus values the app already
/// holds — the vault registry and the associated-token-account derivation.
/// Nothing here is taken from a payload field, a summary, or the API, because
/// the point of this type is to be an INDEPENDENT reading: the initiator and a
/// co-signer run the same decode over the same bytes and must arrive at the same
/// claim. A claim that agreed only because both devices were told the same thing
/// would establish nothing.
struct KaminoDecodedTransaction: Equatable {

    let operation: KaminoKeysignPayload.Operation
    /// The curated vault, resolved from the registry — never a raw address the
    /// bytes named.
    let descriptor: KaminoVaultDescriptor
    /// The `u64` the kvault instruction carries, in the operation's own unit:
    /// underlying-token base units for a deposit, SHARE base units for a
    /// withdraw.
    let amountBaseUnits: BigInt
    /// The sole signer and fee payer — the account that authorises this.
    let signer: String
    /// A deposit into the wrapped-SOL vault opens a wSOL account this
    /// transaction never closes, so its rent stays locked up until the user
    /// withdraws.
    let strandsWrappedSolRent: Bool
    /// The ComputeBudget pair the bytes actually carry, or `nil` when they carry
    /// none.
    ///
    /// Read from the message rather than taken from `chainSpecific`, so the two
    /// can be COMPARED. They are different claims: the payload says what the
    /// initiating device injected, the bytes say what will be charged. A relay
    /// that stripped both instructions would otherwise leave a screen quoting a
    /// priority fee for a transaction that pays none — and the initiating
    /// validator refuses exactly that shape.
    let priorityFee: KaminoPriorityFee?

    /// `true` when a withdraw carries the `u64::MAX` sentinel, which the kVaults
    /// program reads as *withdraw everything* rather than as a share count.
    ///
    /// This app never produces one — `KaminoService` refuses to request it and
    /// the validator pins the instruction's `u64` to the shares that were asked
    /// for — but neither of those runs on a co-signer, which holds only the
    /// relayed bytes. Rendering 18,446,744,073,709.551615 shares would be
    /// literally true and would say nothing about what the transaction does.
    var withdrawsEntirePosition: Bool {
        operation == .withdraw && amountBaseUnits == BigInt(UInt64.max)
    }

    /// The scale `amountBaseUnits` is expressed at, from the registry.
    var amountDecimals: Int {
        switch operation {
        case .deposit: return descriptor.tokenDecimals
        case .withdraw: return descriptor.sharesDecimals
        }
    }

    /// The amount as plain human units — no grouping, no exponent, no locale.
    var amountString: String {
        KaminoBaseUnits.render(baseUnits: amountBaseUnits, decimals: amountDecimals)
    }
}

/// Reads a Kamino deposit or withdraw back out of a raw Solana transaction,
/// **offline**.
///
/// This is what makes a co-signer something other than blind. `SignSolana`
/// carries base64 bytes and nothing else; `KaminoKeysignPayload` is local to the
/// initiating device and never crosses the wire, so a peer holds no claim about
/// the transaction it could be shown. It holds the same registry, the same
/// derivation and the same instruction layouts, though — so it can derive the
/// claim itself.
///
/// Offline is a requirement, not a convenience. The verify and join screens
/// render before any network call is guaranteed to have happened, and a decode
/// that needed an RPC round trip would silently degrade to "no information" on a
/// bad connection — which is exactly the state this exists to remove.
///
/// The cost of being offline is that address lookup tables cannot be resolved:
/// an account index at or above the static key count names an address only that
/// table knows. The vault account is one of those. So the vault is identified
/// the other way round — by deriving each curated vault's share account for this
/// signer and matching it against the instruction's share slot, which is a
/// static key in every observed transaction. That derivation is local, which
/// makes it a stronger identification than reading an address out of the bytes
/// would have been.
///
/// **What this establishes, stated exactly.** Every instruction fits the shape
/// the named operation produces, the amount is the `u64` the kvault instruction
/// carries, the authority is the transaction's own signer, and the share account
/// that instruction spends or credits is the one this signer owns for the named
/// vault's share mint. That is a real claim and it is the one the screen makes.
///
/// It also checks every instruction argument that is a SPEND and is readable
/// without a lookup table: the compute budget's price and limit (their product is
/// the priority fee, a `u64` of micro-lamports bounded on chain only by the
/// payer's balance), and a SOL deposit's wrap transfer — its amount against the
/// deposit, its source against the signer, and its destination against the
/// locally derived wrapped-SOL account.
///
/// **What it does not establish.** The account identities that live in the lookup
/// table. Two consequences follow and neither is papered over: the vault slot is
/// compared only when it happens to be a static key, and the accounts an ATA
/// creation names cannot be resolved. The initiating device closes both gaps —
/// `KaminoTransactionValidator` resolves the tables from the RPC and checks every
/// account before the payload exists — so the residue is what a *relayed*
/// transaction can hide from a co-signer, and it is bounded twice over: by the
/// sequence, which refuses an instruction the template does not name, and by the
/// argument checks above, which refuse the spends it could have inflated.
enum KaminoTransactionDecoder {

    /// Whether these bytes invoke the kVaults program at all.
    ///
    /// Separate from `decode` on purpose: a transaction that invokes `kvault`
    /// but cannot be decoded must be surfaced as unreadable rather than as an
    /// ordinary Solana transaction. Program ids are always static keys — the
    /// parser refuses a `programIdIndex` outside them — so this needs no lookup
    /// table either.
    static func invokesKaminoVault(_ transaction: SolanaV0Transaction) -> Bool {
        let accounts = transaction.staticAccountAddresses
        return transaction.instructions.contains { instruction in
            let index = Int(instruction.programIdIndex)
            guard accounts.indices.contains(index) else { return false }
            return accounts[index] == KaminoVaultRegistry.programId
        }
    }

    /// Whether bytes this app cannot parse nonetheless mention the kVaults
    /// program.
    ///
    /// The structured check above needs a v0 message. `SolanaHelper` signs a raw
    /// payload's wire bytes verbatim and does not care what version they are, so
    /// a LEGACY transaction invoking kVaults would parse to nothing and — without
    /// this — be classified as an ordinary Solana payload and sail past both
    /// signing guards. A program id is a 32-byte account key in the message under
    /// either format, so scanning for those bytes answers the only question that
    /// matters here: is this something we must refuse to stay quiet about?
    ///
    /// Deliberately coarse, and coarse in the safe direction. A payload that
    /// happens to contain these 32 bytes without invoking the program would be
    /// refused; a payload that invokes the program cannot escape.
    static func mentionsKaminoVaultProgram(base64Transaction: String) -> Bool {
        guard let data = Data(base64Encoded: base64Transaction),
              let key = Base58.decodeNoCheck(string: KaminoVaultRegistry.programId),
              key.count == 32,
              data.count >= key.count
        else { return false }

        let bytes = [UInt8](data)
        let needle = [UInt8](key)
        for start in 0...(bytes.count - needle.count) where Array(bytes[start..<start + needle.count]) == needle {
            return true
        }
        return false
    }

    /// Decodes the single kvault deposit or withdraw these bytes perform, or
    /// `nil` when they do not perform exactly one that this app recognises.
    ///
    /// `nil` is a refusal to describe, never a "probably fine". Every guard
    /// below is a case where the honest answer is that the bytes are not the
    /// shape this decoder knows how to read.
    static func decode(_ transaction: SolanaV0Transaction) -> KaminoDecodedTransaction? {
        let accounts = transaction.staticAccountAddresses
        guard let signer = accounts.first else { return nil }

        let programs = transaction.instructions.map { instruction -> KaminoSolanaProgram? in
            let index = Int(instruction.programIdIndex)
            guard accounts.indices.contains(index) else { return nil }
            return KaminoSolanaProgram(programId: accounts[index])
        }
        let kinds = zip(programs, transaction.instructions).map { program, instruction in
            KaminoInstructionSequence.kind(program: program, data: instruction.data)
        }

        // Exactly one kvault instruction. Two would mean two amounts and two
        // vaults, and picking either to display would be a guess.
        let vaultPositions = kinds.indices.filter {
            kinds[$0] == .kvaultDeposit || kinds[$0] == .kvaultWithdraw
        }
        guard vaultPositions.count == 1, let position = vaultPositions.first else { return nil }
        let operation: KaminoKeysignPayload.Operation = kinds[position] == .kvaultDeposit ? .deposit : .withdraw

        let instruction = transaction.instructions[position]
        guard let amount = KaminoInstructionDiscriminator.anchorArgument(instruction.data) else { return nil }

        let layout = Layout(operation: operation)
        guard instruction.accountIndexes.count >= layout.minimumCount else { return nil }

        // The authority slot must be this transaction's own signer. Without it
        // the amount and the vault would describe an instruction that some other
        // account authorises, which is not what the user is being asked to
        // approve.
        guard staticAddress(accounts, instruction.accountIndexes[layout.user]) == signer else { return nil }

        guard let shareAccount = staticAddress(accounts, instruction.accountIndexes[layout.userShareAccount]),
              let descriptor = descriptor(forShareAccount: shareAccount, owner: signer)
        else { return nil }

        // When the vault slot happens to be a static key, it must be the vault
        // the share account identified. It is a lookup-table entry in every
        // captured transaction — see the type's doc for what that costs — but an
        // attacker who moved it into the static keys must not thereby escape the
        // comparison.
        if let namedVault = staticAddress(accounts, instruction.accountIndexes[layout.vault]),
           namedVault != descriptor.address {
            return nil
        }

        // EVERY instruction must fit the shape this operation produces — not
        // just the one that was recognised. This is the check that stops a
        // transfer riding alongside a plausible deposit: the decode either
        // accounts for the whole transaction or it describes none of it.
        let steps = KaminoInstructionSequence.expected(
            operation: operation,
            isWrappedSolVault: descriptor.tokenMint == KaminoVaultRegistry.wrappedSolMint,
            hasFarm: descriptor.farm != nil,
            // Read from the bytes rather than assumed: the pre-injection form
            // never leaves the preparer, but a relayed transaction is whatever
            // it is, and the template has to describe the one in hand.
            hasPriorityFee: kinds.contains(.computeUnitLimit) || kinds.contains(.computeUnitPrice)
        )
        guard case .success(let matched) = KaminoInstructionSequence.match(kinds: kinds, against: steps) else {
            return nil
        }

        // Matching the shape is not the same as accepting the numbers. Some of
        // what a matched instruction carries IS readable without a lookup table,
        // and every one of those is a spend — so they are checked here rather
        // than left to the doc comment. What stays unreadable is the account
        // identities, which is the residue the type's doc names.
        guard let arguments = readArguments(
            matched: matched,
            transaction: transaction,
            accounts: accounts,
            signer: signer,
            operation: operation,
            amount: amount,
            descriptor: descriptor
        ) else { return nil }

        return KaminoDecodedTransaction(
            operation: operation,
            descriptor: descriptor,
            amountBaseUnits: BigInt(amount),
            signer: signer,
            strandsWrappedSolRent: operation == .deposit
                && descriptor.tokenMint == KaminoVaultRegistry.wrappedSolMint,
            priorityFee: arguments.priorityFee
        )
    }

    /// Convenience over the raw payload: exactly one transaction, parseable.
    ///
    /// More than one is refused rather than summarised from the first. Nothing
    /// this app builds sends a batch, and describing one of several would put a
    /// claim on screen that is true of only part of what gets signed.
    static func decode(rawTransactions: [String]) -> KaminoDecodedTransaction? {
        guard rawTransactions.count == 1,
              let transaction = try? SolanaV0Transaction(base64Transaction: rawTransactions[0])
        else { return nil }
        return decode(transaction)
    }

    // MARK: - Private

    /// What reading every matched instruction's arguments produced, or `nil`
    /// when one of them is not acceptable.
    private struct Arguments {
        var priorityFee: KaminoPriorityFee?
    }

    /// Checks every instruction contract that can be judged offline, and reads
    /// out the one value the presentation needs to cross-check.
    ///
    /// Three kinds of check, and all three are things the online validator also
    /// makes — the point is that a co-signer should refuse what the initiating
    /// device would have refused, minus only what genuinely needs the network:
    ///
    /// - **Amounts that are spends.** `limit × price` is the priority fee, a
    ///   `u64` of micro-lamports bounded on chain only by the payer's balance, so
    ///   both halves are pinned to exactly what this app injects. A SOL deposit's
    ///   `System::transfer` must move exactly the deposit, out of the signer,
    ///   into the locally derived wrapped-SOL account.
    /// - **Arguments that encode behaviour.** `farms::stake` takes `u64::MAX`,
    ///   meaning "stake the whole share balance". A different value is a
    ///   behaviour change, not a variation.
    /// - **Account cardinality.** Not identity — that needs the lookup table —
    ///   but an instruction with too few accounts to be what it claims is
    ///   malformed, and that is readable from the indices alone.
    private static func readArguments(
        matched: [KaminoInstructionSequence.Kind],
        transaction: SolanaV0Transaction,
        accounts: [String],
        signer: String,
        operation: KaminoKeysignPayload.Operation,
        amount: UInt64,
        descriptor: KaminoVaultDescriptor
    ) -> Arguments? {
        var arguments = Arguments()
        var limit: UInt32?
        var price: UInt64?

        for (position, kind) in matched.enumerated() {
            let data = transaction.instructions[position].data
            let indexes = transaction.instructions[position].accountIndexes

            switch kind {
            case .computeUnitPrice:
                guard indexes.isEmpty,
                      let value = KaminoInstructionDiscriminator.computeUnitPrice(data),
                      value <= KaminoComputeBudget.maxUnitPriceMicroLamports
                else { return nil }
                price = value

            case .computeUnitLimit:
                guard indexes.isEmpty,
                      let value = KaminoInstructionDiscriminator.computeUnitLimit(data),
                      value == expectedUnitLimit(operation: operation, descriptor: descriptor)
                else { return nil }
                limit = value

            case .wrapSolTransfer:
                guard operation == .deposit,
                      let lamports = KaminoInstructionDiscriminator.systemTransferLamports(data),
                      lamports == amount,
                      indexes.count >= KaminoInstructionAccounts.SystemTransfer.count,
                      staticAddress(accounts, indexes[KaminoInstructionAccounts.SystemTransfer.source]) == signer
                else { return nil }
                // The destination is the user's own wrapped-SOL account whenever
                // it resolves statically — and it does in every captured
                // transaction.
                if let destination = staticAddress(
                    accounts,
                    indexes[KaminoInstructionAccounts.SystemTransfer.destination]
                ) {
                    guard SolanaAssociatedTokenAccount
                        .ownedAccounts(owner: signer, mint: descriptor.tokenMint)
                        .contains(destination)
                    else { return nil }
                }

            case .farmsStake:
                guard indexes.count >= KaminoInstructionAccounts.FarmsStake.minimumCount,
                      KaminoInstructionDiscriminator.anchorArgument(data) == UInt64.max
                else { return nil }

            case .farmsInitializeUser:
                guard indexes.count >= KaminoInstructionAccounts.FarmsInitializeUser.minimumCount
                else { return nil }

            case .createTokenAccount:
                guard indexes.count >= KaminoInstructionAccounts.AssociatedToken.count else { return nil }

            case .closeTokenAccount:
                guard indexes.count >= KaminoInstructionAccounts.CloseAccount.count else { return nil }

            case .syncNative:
                guard !indexes.isEmpty else { return nil }

            case .kvaultDeposit, .kvaultWithdraw:
                // Already read: the amount, the authority and the share account.
                continue
            }
        }

        // Both halves or neither. The template already enforces that, but the
        // pair is what the fee is, so it is assembled rather than assumed.
        switch (limit, price) {
        case (let limit?, let price?):
            arguments.priorityFee = KaminoPriorityFee(limit: limit, price: price)
        case (nil, nil):
            arguments.priorityFee = nil
        default:
            return nil
        }
        return arguments
    }

    /// The compute unit limit this app injects for this operation and vault.
    /// Pinned rather than bounded: the app injects exactly one value, so any
    /// other one did not come from it.
    private static func expectedUnitLimit(
        operation: KaminoKeysignPayload.Operation,
        descriptor: KaminoVaultDescriptor
    ) -> UInt32 {
        switch operation {
        case .deposit:
            return descriptor.tokenMint == KaminoVaultRegistry.wrappedSolMint
                ? KaminoComputeBudget.nativeDepositUnitLimit
                : KaminoComputeBudget.tokenDepositUnitLimit
        case .withdraw:
            return KaminoComputeBudget.withdrawUnitLimit
        }
    }

    /// The curated vault whose share account for `owner` is `account`.
    ///
    /// The share mint is pinned per vault in the registry and the ATA is a
    /// program-derived address, so this is a local computation over a
    /// three-element allow-list. Both token programs are tried because a mint
    /// belongs to exactly one and which one is not knowable from the address.
    private static func descriptor(
        forShareAccount account: String,
        owner: String
    ) -> KaminoVaultDescriptor? {
        KaminoVaultRegistry.allowList.first { descriptor in
            SolanaAssociatedTokenAccount
                .ownedAccounts(owner: owner, mint: descriptor.sharesMint)
                .contains(account)
        }
    }

    /// The address at `index`, or `nil` when it lives in an address lookup table
    /// this decode cannot resolve. Fail-closed: an unresolvable slot is never
    /// treated as a match.
    private static func staticAddress(_ accounts: [String], _ index: UInt8) -> String? {
        let position = Int(index)
        guard accounts.indices.contains(position) else { return nil }
        return accounts[position]
    }

    private struct Layout {
        let user: Int
        let vault: Int
        let userShareAccount: Int
        let minimumCount: Int

        init(operation: KaminoKeysignPayload.Operation) {
            switch operation {
            case .deposit:
                user = KaminoInstructionAccounts.KvaultDeposit.user
                vault = KaminoInstructionAccounts.KvaultDeposit.vault
                userShareAccount = KaminoInstructionAccounts.KvaultDeposit.userShareAccount
                minimumCount = KaminoInstructionAccounts.KvaultDeposit.minimumCount
            case .withdraw:
                user = KaminoInstructionAccounts.KvaultWithdraw.user
                vault = KaminoInstructionAccounts.KvaultWithdraw.vault
                userShareAccount = KaminoInstructionAccounts.KvaultWithdraw.userShareAccount
                minimumCount = KaminoInstructionAccounts.KvaultWithdraw.minimumCount
            }
        }
    }
}
