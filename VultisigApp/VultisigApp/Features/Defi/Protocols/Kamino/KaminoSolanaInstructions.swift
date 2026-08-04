//
//  KaminoSolanaInstructions.swift
//  VultisigApp
//

import Foundation

/// Every program a Kamino Earn transaction is allowed to invoke.
///
/// This is an allow-list, not a catalogue: an instruction whose program is not
/// one of these is a refusal. That matters because the transaction is built by
/// Kamino and signed verbatim, so the program set is the outer boundary on what
/// the user's single signature can authorise. Anything outside it is code we
/// never agreed to run.
enum KaminoSolanaProgram: String, CaseIterable {
    case system = "11111111111111111111111111111111"
    case token = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    case token2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
    case associatedToken = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"
    case computeBudget = "ComputeBudget111111111111111111111111111111"
    case kvault = "KvauGMspG5k6rtzrqqn7WNn3oZdyKqLKwK2XWQ8FLjd"
    case farms = "FarmsPZpWu9i7Kky8tPN37rs2TpmMrAZrC7S7vJa91Hr"

    init?(programId: String) {
        self.init(rawValue: programId)
    }

    /// Programs whose instructions Kamino's builder composes itself, rather than
    /// reaching them through a CPI from its own programs.
    ///
    /// The distinction is the crux of the writable-account check. What `kvault`
    /// and `farms` do with the accounts they are handed is the protocol we chose
    /// to trust; what appears at the *top level* of the transaction is whatever
    /// the builder decided to put there, so every account those instructions can
    /// write to has to be one we can name.
    var isBuilderComposed: Bool {
        switch self {
        case .system, .token, .token2022, .associatedToken:
            return true
        case .computeBudget, .kvault, .farms:
            return false
        }
    }

    var isTokenProgram: Bool {
        self == .token || self == .token2022
    }
}

/// Instruction discriminators for the programs a Kamino Earn transaction uses.
///
/// The four Anchor ones are `sha256("global:<name>")[0..<8]`, and each was also
/// read back out of a mainnet-simulated transaction built by the Kamino API, so
/// the constant and the observation agree.
enum KaminoInstructionDiscriminator {

    /// `kvault::deposit(u64 tokenAmount)`.
    static let kvaultDeposit: [UInt8] = [0xf2, 0x23, 0xc6, 0x89, 0x52, 0xe1, 0xf2, 0xb6]
    /// `kvault::withdraw(u64 shareAmount)` — the argument is in SHARES, the
    /// inverse of deposit's unit.
    static let kvaultWithdraw: [UInt8] = [0xb7, 0x12, 0x46, 0x9c, 0x94, 0x6d, 0xa1, 0x22]
    /// `farms::initialize_user` — creates the user's farm state. Absent when it
    /// already exists.
    static let farmsInitializeUser: [UInt8] = [0x6f, 0x11, 0xb9, 0xfa, 0x3c, 0x7a, 0x26, 0xfe]
    /// `farms::stake(u64 amount)`. Kamino always passes `u64::MAX`, meaning
    /// "stake the whole share balance".
    static let farmsStake: [UInt8] = [0xce, 0xb0, 0xca, 0x12, 0xc8, 0xd1, 0xb3, 0x6c]

    /// Associated Token Program `CreateIdempotent`.
    static let createIdempotentAssociatedTokenAccount: UInt8 = 1

    /// SPL Token `SyncNative` — reconciles a wSOL account's token balance with
    /// the lamports that were just transferred into it.
    static let tokenSyncNative: UInt8 = 17
    /// SPL Token `CloseAccount` — on the Kamino path this unwraps wSOL back to
    /// native SOL, or reclaims the rent of an emptied token account.
    static let tokenCloseAccount: UInt8 = 9

    /// System Program `Transfer`, whose discriminant is a 4-byte little-endian
    /// enum index rather than a single byte.
    static let systemTransfer: [UInt8] = [2, 0, 0, 0]
    /// `Transfer` payload: the 4-byte discriminant plus a `u64` lamport amount.
    static let systemTransferDataLength = 12

    /// An Anchor instruction's `u64` argument: the 8 bytes after the
    /// discriminator, little-endian.
    static func anchorArgument(_ data: [UInt8]) -> UInt64? {
        guard data.count == 16 else { return nil }
        return littleEndianUInt64(data[8..<16])
    }

    static func systemTransferLamports(_ data: [UInt8]) -> UInt64? {
        guard data.count == systemTransferDataLength else { return nil }
        return littleEndianUInt64(data[4..<12])
    }

    /// `SetComputeUnitLimit`'s `u32` argument.
    static func computeUnitLimit(_ data: [UInt8]) -> UInt32? {
        guard data.count == 5, data[0] == ComputeBudgetInstruction.setUnitLimit else { return nil }
        return UInt32(truncatingIfNeeded: littleEndianUInt64(data[1..<5]))
    }

    /// `SetComputeUnitPrice`'s `u64` argument, in micro-lamports per compute
    /// unit. The fee it produces is `price × limit`, so this is a spend.
    static func computeUnitPrice(_ data: [UInt8]) -> UInt64? {
        guard data.count == 9, data[0] == ComputeBudgetInstruction.setUnitPrice else { return nil }
        return littleEndianUInt64(data[1..<9])
    }

    private static func littleEndianUInt64(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        bytes.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }
}

// MARK: - Account layouts

/// Positions of the accounts each instruction is checked and decoded on.
///
/// An Anchor instruction's account list is fixed by its IDL — only the trailing
/// `remaining_accounts` vary, which is why the observed lists differ in length
/// between vaults while these prefixes do not. Each index below was read out of
/// transactions the Kamino API built for all three launch vaults.
///
/// Shared rather than duplicated: `KaminoTransactionValidator` checks against
/// these before signing and `KaminoTransactionDecoder` reads the same slots back
/// out of the signed bytes. Two copies that drifted would let the verify screen
/// describe a different instruction from the one that was validated.
enum KaminoInstructionAccounts {

    enum KvaultDeposit {
        static let user = 0
        static let vault = 1
        static let tokenMint = 3
        static let sharesMint = 5
        static let userTokenAccount = 6
        static let userShareAccount = 7
        static let minimumCount = 8
    }

    enum KvaultWithdraw {
        static let user = 0
        static let vault = 1
        static let userTokenAccount = 5
        static let tokenMint = 6
        static let userShareAccount = 7
        static let sharesMint = 8
        static let minimumCount = 9
    }

    enum FarmsInitializeUser {
        static let authority = 0
        static let farm = 5
        static let minimumCount = 6
    }

    enum FarmsStake {
        static let owner = 0
        static let farm = 2
        static let userShareAccount = 4
        static let sharesMint = 5
        static let minimumCount = 6
    }

    enum AssociatedToken {
        static let payer = 0
        static let account = 1
        static let wallet = 2
        static let mint = 3
        static let tokenProgram = 5
        static let count = 6
    }

    enum SystemTransfer {
        static let source = 0
        static let destination = 1
        static let count = 2
    }

    enum CloseAccount {
        static let account = 0
        static let destination = 1
        static let authority = 2
        static let count = 3
    }
}
