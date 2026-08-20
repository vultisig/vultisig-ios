//
//  DecodedTransaction.swift
//  VultisigApp
//
//  A provenance-aware reading of signed transaction content. Amounts remain in
//  raw base units; scaling with unsigned display metadata happens later.
//

import BigInt
import Foundation

/// What the amount is denominated in.
enum DecodedAsset: Hashable {

    /// A denomination named by signed content.
    case denom(String)

    /// The transaction coin; its display metadata is resolved separately.
    case transactionCoin

    /// The instruction's fixed native asset, rendered from bundled metadata.
    case chainNative
}

/// The quantity, or the share of a position, a transaction moves.
enum DecodedAmount: Hashable {

    /// Base units exactly as the signed content carries them.
    case units(BigInt, of: DecodedAsset)

    /// A signed share in basis points; resolving the position is enrichment.
    case fraction(basisPoints: Int, of: DecodedAsset)

    /// The signed operation names no quantity.
    case unstated
}

/// One asset-independent verb per operation. `CaseIterable` lets vocabulary
/// tests require an explicit presentation decision for every case.
enum DecodedOperation: Hashable, CaseIterable {
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

    /// Nothing readable identified the operation; never inferred as a transfer.
    case unknown
}

/// Who or what the operation is directed at, when the transaction names one.
enum DecodedCounterparty: Hashable {
    case node(String)
    case validator(String)
    case pool(String)
    case contract(String)
}

/// Evidence for the reading, ordered strongest first.
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
