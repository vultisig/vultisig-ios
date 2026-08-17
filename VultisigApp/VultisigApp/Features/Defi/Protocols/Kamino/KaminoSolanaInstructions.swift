//
//  KaminoSolanaInstructions.swift
//  VultisigApp
//

import BigInt
import Foundation
import WalletCore

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
    /// SPL Memo v3, carrying this app's attribution tag. Never present in what
    /// Kamino builds — the app appends it, which is why a memo arriving from the
    /// API is a refusal rather than something to pass through.
    case memo = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"

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
        case .computeBudget, .kvault, .farms, .memo:
            return false
        }
    }

    var isTokenProgram: Bool {
        self == .token || self == .token2022
    }
}

/// The attribution tag this app writes into every Kamino transaction it builds.
///
/// Kamino's kvault API takes no referrer or partner parameter, so attribution is
/// client-side: one SPL Memo instruction carrying this literal, appended after
/// the API has built the transaction and before it is validated and signed.
///
/// The bytes are the whole point. This tag is the filter every downstream
/// measurement of Vultisig-originated deposits keys on — Kamino's own
/// attribution and the public Dune queries alike — and it has to be
/// byte-identical here, on Android and on Windows. So it is written once, and
/// the injector, the validator and the verify-screen decoder all read it from
/// here rather than each spelling it out.
enum KaminoAttribution {
    static let memoTag = "8k2mz"
    static let memoTagBytes = [UInt8](Data(memoTag.utf8))
}

/// Instruction discriminators for the programs a Kamino Earn transaction uses.
///
/// The seven Anchor ones are `sha256("global:<name>")[0..<8]`, and each was also
/// read back out of a mainnet-simulated transaction built by the Kamino API, so
/// the constant and the observation agree.
///
/// That agreement is the point, and it is what makes these named rather than
/// pasted. A constant copied out of a captured transaction matches the shape it
/// was copied from and asserts nothing; one derived from the instruction's name
/// and *then* found in the bytes says the bytes are that instruction.
enum KaminoInstructionDiscriminator {

    /// `kvault::deposit(u64 tokenAmount)`.
    static let kvaultDeposit: [UInt8] = [0xf2, 0x23, 0xc6, 0x89, 0x52, 0xe1, 0xf2, 0xb6]
    /// `kvault::withdraw(u64 shareAmount)` — the argument is in SHARES, the
    /// inverse of deposit's unit.
    ///
    /// One of TWO instructions a withdraw arrives as; see
    /// `kvaultWithdrawFromAvailable`. This is the one the builder emits when the
    /// request does not fit the vault's liquid buffer, because only this one
    /// carries the accounts needed to pull the shortfall out of a lending
    /// reserve.
    static let kvaultWithdraw: [UInt8] = [0xb7, 0x12, 0x46, 0x9c, 0x94, 0x6d, 0xa1, 0x22]
    /// `kvault::withdraw_from_available(u64 shareAmount)` — the same withdraw,
    /// served entirely out of the vault's liquid buffer.
    ///
    /// Which of the two arrives is a fact about the VAULT's liquidity at build
    /// time, not about the user's request: Kamino's builder emits this one when
    /// the reserves need not be touched and `withdraw` when they must, and both
    /// are in live use. So both are accepted, and both mean the same thing to
    /// the person signing — burn this many shares from this account, pay out to
    /// that one.
    ///
    /// Reading one under the other's account map is safe, and that is checked
    /// rather than assumed: the program's IDL declares `withdraw`'s accounts as
    /// `withdraw_from_available`'s fourteen followed by the reserve group, so the
    /// two share a prefix by construction. Every index in
    /// `KaminoInstructionAccounts.KvaultWithdraw` lies inside it.
    static let kvaultWithdrawFromAvailable: [UInt8] = [0x13, 0x83, 0x70, 0x9b, 0xaa, 0xdc, 0x22, 0x39]
    /// `farms::initialize_user` — creates the user's farm state. Absent when it
    /// already exists.
    static let farmsInitializeUser: [UInt8] = [0x6f, 0x11, 0xb9, 0xfa, 0x3c, 0x7a, 0x26, 0xfe]
    /// `farms::stake(u64 amount)`. Kamino always passes `u64::MAX`, meaning
    /// "stake the whole share balance".
    static let farmsStake: [UInt8] = [0xce, 0xb0, 0xca, 0x12, 0xc8, 0xd1, 0xb3, 0x6c]
    /// `farms::unstake(u128 stakeSharesScaled)` — releases shares from the farm
    /// into the user's pending-withdrawal balance.
    ///
    /// Its argument is the only `u128` in this feature, and it is scaled: the
    /// farms program holds stake at `WAD`, so the value is share base units
    /// multiplied by `10^18`. Reading those 16 bytes as a `u64` truncates
    /// silently — see `farmsStakeScale` and `anchorArgument128`.
    static let farmsUnstake: [UInt8] = [0x5a, 0x5f, 0x6b, 0x2a, 0xcd, 0x7c, 0x32, 0xe1]
    /// `farms::withdraw_unstaked_deposits` — moves what `unstake` released into
    /// the user's share account, where the vault withdraw can then burn it.
    /// Takes no argument: it always moves the whole pending balance.
    static let farmsWithdrawUnstakedDeposits: [UInt8] = [0x24, 0x66, 0xbb, 0x31, 0xdc, 0x24, 0x84, 0x43]

    /// The fixed-point scale the farms program holds stake at: `10^18`.
    ///
    /// Everything else in this feature is an integer count of base units. This
    /// one is not, so the conversion is written out rather than inferred at each
    /// call site.
    static let farmsStakeScale = BigInt(10).power(18)

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

    /// An Anchor instruction's `u128` argument: the 16 bytes after the
    /// discriminator, little-endian, as an exact `BigInt`.
    ///
    /// Separate from `anchorArgument` and never a fallback for it. A `u128`
    /// argument read through the `u64` reader would take the low 8 bytes of a
    /// 16-byte field and report a number that is not the one on the wire —
    /// `1 share × 10^18` is `0x0D3C21BCECCEDA1000000`, whose low 8 bytes are
    /// `0xBCECCEDA1000000`, a plausible-looking value that means nothing. So the
    /// two readers are keyed on the exact payload length and neither accepts the
    /// other's.
    static func anchorArgument128(_ data: [UInt8]) -> BigInt? {
        guard data.count == 24 else { return nil }
        return data[8..<24].reversed().reduce(BigInt(0)) { $0 << 8 | BigInt($1) }
    }

    /// An Anchor instruction that carries no argument at all: exactly the
    /// discriminator and nothing after it.
    ///
    /// Checked rather than assumed. `kind(program:data:)` matches on the first
    /// eight bytes, so trailing bytes would otherwise ride along unread.
    static func hasNoAnchorArgument(_ data: [UInt8]) -> Bool {
        data.count == 8
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

/// The farms program's per-user account, derived rather than trusted.
///
/// `farms::unstake` and `farms::withdraw_unstaked_deposits` both take it, and it
/// is the account that decides WHICH stake they move. Its address is a program
/// address over the farm and the owner, so recomputing it locally binds both
/// instructions to one farm and one user at once — and it does so **offline**,
/// which the farm slot itself cannot: the farm is an address-lookup-table entry
/// in every captured transaction, and the verify screen has no way to resolve
/// one.
///
/// The user state is a static key in every captured transaction, in both the
/// as-built and compute-budget-injected forms, which is what makes this
/// checkable there at all.
enum KaminoFarmsUserState {

    /// The farms program's own seed prefix for this account.
    static let seed = Data("user".utf8)

    /// The user state for `owner` in `farm`, or `nil` when it cannot be derived.
    static func derive(farm: String, owner: String) -> String? {
        guard let farmKey = Base58.decodeNoCheck(string: farm),
              let ownerKey = Base58.decodeNoCheck(string: owner),
              farmKey.count == 32,
              ownerKey.count == 32
        else { return nil }

        return SolanaProgramDerivedAddress.find(
            seeds: [seed, farmKey, ownerKey],
            programId: KaminoSolanaProgram.farms.rawValue
        )
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

    /// `kvault::withdraw` AND `kvault::withdraw_from_available`, which share
    /// these positions rather than merely happening to agree on them.
    ///
    /// The program's IDL declares `withdraw`'s account list as the
    /// `withdraw_from_available` group — all fourteen of its accounts, in order —
    /// followed by the reserve-exit group and the event pair. So the first
    /// fourteen slots of the longer instruction ARE the shorter one's, and every
    /// index below is inside that shared prefix. Confirmed on the wire too: the
    /// same wallet's withdraw from one vault, built both ways minutes apart,
    /// resolves to identical pubkeys through slot 13 and first differs at 14.
    ///
    /// This is why one index map serves both. If it did not, the verify screen
    /// would name a vault, a mint or a payout account that the instruction being
    /// signed does not actually put there.
    enum KvaultWithdraw {
        static let user = 0
        static let vault = 1
        static let userTokenAccount = 5
        static let tokenMint = 6
        static let userShareAccount = 7
        static let sharesMint = 8
        static let minimumCount = 9
        /// The number of accounts the two withdraw instructions share, and the
        /// bound every index above must stay under.
        static let sharedPrefixCount = 14
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

    /// `farms::unstake`. Four accounts, and the fourth is the farms program's own
    /// id — Anchor's encoding of an absent optional account — so only the first
    /// three name anything.
    enum FarmsUnstake {
        static let owner = 0
        static let userState = 1
        static let farm = 2
        static let minimumCount = 3
    }

    /// `farms::withdraw_unstaked_deposits`. The share account at index 3 is where
    /// the released shares land, and it is the same account the vault withdraw
    /// then burns from — which is what ties the two halves of a staked withdraw
    /// to one user.
    enum FarmsWithdrawUnstakedDeposits {
        static let owner = 0
        static let userState = 1
        static let farm = 2
        static let userShareAccount = 3
        static let minimumCount = 4
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
