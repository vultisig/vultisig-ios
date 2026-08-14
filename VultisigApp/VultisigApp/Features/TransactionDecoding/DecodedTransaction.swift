//
//  DecodedTransaction.swift
//  VultisigApp
//
//  What a transaction turned out to be, once something that will actually be
//  signed has been read.
//
//  ⚠️ **Amounts are raw base units here, never a human figure.**
//
//  Scaling base units into "1.5 TCY" needs `decimals`, and `decimals` — like
//  `ticker` and `contractAddress` — is payload metadata that the chain does not
//  commit to. An initiator can change it without changing a single signed byte,
//  which would let the same transaction read as 1, as 0.00000001, or as ten
//  billion on the device being asked to approve it. That is exactly the
//  free-contradiction defect that ruled out declaring the operation on the wire,
//  and a decoder that scaled here would reintroduce it one level down.
//
//  So decoding stops at the last honest point: the units the signed content
//  carries, and the asset that content names. Turning those into something a
//  person reads is a presentation decision, made in one place where the fact
//  that it leans on unsigned metadata can be stated rather than hidden.
//

import BigInt
import Foundation

/// What the amount is denominated in.
enum DecodedAsset: Hashable {

    /// A denom the signed content names outright — a wasm coin's denom, a
    /// memo's asset field. In the bytes, so it cannot disagree with them.
    case denom(String)

    /// The transaction's own coin. Which asset moves is settled by the chain
    /// and the address, but the TICKER and DECIMALS used to render it come from
    /// payload metadata the signature does not cover.
    case transactionCoin
}

/// The quantity, or the share of a position, a transaction moves.
enum DecodedAmount: Hashable {

    /// Base units exactly as the signed content carries them.
    case units(BigInt, of: DecodedAsset)

    /// A share of a position in ten-thousandths — the unit THORChain's
    /// `tcy-:<bps>` and MAYAChain's `POOL-:<bps>` memos carry, and the only
    /// thing those transactions commit to. Resolving it against the staked
    /// position is enrichment, and needs a network read, so it is deliberately
    /// not decoding's job.
    case fraction(basisPoints: Int, of: DecodedAsset)

    /// The transaction names no quantity, and no reading of it can. A rewards
    /// claim carries no coin; a node LEAVE moves nothing; a vault deposit
    /// attaches what it SPENDS and says nothing about what it mints.
    case unstated
}

/// What the transaction does.
///
/// One verb per operation rather than per asset: a TCY stake, a RUJI stake and a
/// TON pool deposit are all `.stake`.
enum DecodedOperation: Hashable {
    case transfer
    case swap
    case approve
    case stake
    case unstake
    case bond
    case unbond
    case rebond
    case leave
    case delegate
    case undelegate
    case redelegate
    case claimRewards
    case mint
    case redeem
    case addLiquidity
    case removeLiquidity
    case merge
    case unmerge
    case ibcTransfer
    case vote
    /// Moving a token into THORChain's secured-asset layer, or back out.
    case securedAssetDeposit
    case securedAssetWithdraw
    /// Moving a token to THORChain from the chain it lives on now.
    case switchChain
    case limitOrderPlacement
    case limitOrderCancel
    /// Recognised as a contract call without a known shape behind it.
    case contractCall

    /// ⚠️ Nothing readable said what this is — NOT "an ordinary transfer".
    ///
    /// The distinction is the whole difference between describing and guessing.
    /// A payload carrying a memo nobody parses, or a SignDoc no decoder
    /// understands, is not a send just because a send is the common case; saying
    /// so would be inventing a reading, which is the failure this component
    /// exists to prevent. Screens render `.unknown` as whatever they showed
    /// before any of this existed.
    case unknown
}

/// Who or what the operation is directed at, when the transaction names one.
enum DecodedCounterparty: Hashable {
    case node(String)
    case validator(String)
    case pool(String)
    case contract(String)
}

/// What the reading rests on.
///
/// Recorded rather than inferred, because it is the difference between a
/// description the transaction cannot contradict and one it can. Ordered
/// strongest first, and `Comparable` so "no weaker than" is expressible rather
/// than a comment.
enum DecodedEvidence: Int, Comparable, Hashable {
    /// The literal object being signed — a SignDoc, a raw transaction, a BOC.
    case signedData = 0
    /// The contract call that gets signed, naming its own action.
    case wasmExecuteMsg = 1
    /// The string the chain itself parses.
    case memo = 2
    /// Structured intent that builds the signed bytes.
    case structuredPayload = 3
    /// The wire discriminator that selects the signing shape.
    case wireTransactionType = 4
    /// Nothing was read. Only ever paired with `.unknown`.
    case unread = 5

    static func < (lhs: DecodedEvidence, rhs: DecodedEvidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether this evidence is at least as strong as `other`.
    func isNoWeaker(than other: DecodedEvidence) -> Bool {
        rawValue <= other.rawValue
    }
}

struct DecodedTransaction: Hashable {
    let operation: DecodedOperation
    let amount: DecodedAmount
    let counterparty: DecodedCounterparty?
    let evidence: DecodedEvidence

    init(
        operation: DecodedOperation,
        amount: DecodedAmount,
        counterparty: DecodedCounterparty? = nil,
        evidence: DecodedEvidence
    ) {
        self.operation = operation
        self.amount = amount
        self.counterparty = counterparty
        self.evidence = evidence
    }

    /// Nothing readable identified this transaction.
    static let unreadable = DecodedTransaction(
        operation: .unknown,
        amount: .unstated,
        evidence: .unread
    )
}
