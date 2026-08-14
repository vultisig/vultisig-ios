//
//  SignedTransactionContent.swift
//  VultisigApp
//
//  What a transaction decoder is allowed to look at.
//
//  Deliberately a SURFACE rather than a type. The two devices hold different
//  objects at the moment they have to describe a transaction — an initiator has
//  its `SendTransaction`, a co-signer has the `KeysignPayload` it was asked to
//  sign — and the initiator does not have a payload at all when its Verify
//  screen renders (`createKeysignPayload` runs from the sign action, after the
//  screen is already up). Decoding through one protocol they both satisfy means
//  the two cannot describe the same transaction differently; if they ever do,
//  that is a bug with a failing test rather than an architectural fact.
//
//  ⚠️ **Every member here is content that shapes what gets signed.** That is the
//  whole point: a reading derived from these fields cannot be contradicted by
//  the transaction without the transaction itself changing. Anything merely
//  asserted alongside the signed bytes does not belong in this protocol, however
//  convenient it would be to switch on — that was the defect in carrying a
//  declared kind on the wire, and admitting one here would reintroduce it behind
//  a better-looking type.
//

import BigInt
import Foundation
import VultisigCommonData

protocol SignedTransactionContent {
    var coin: Coin { get }
    var toAddress: String { get }
    /// Base units, as the transaction will carry them.
    var toAmountRaw: BigInt { get }
    /// `nil` rather than `""` for "no memo": an empty memo and an absent one
    /// mean the same thing to every chain here, and settling on one spelling
    /// saves every decoder from checking both.
    var signedMemo: String? { get }
    /// The wire discriminator that already selects how the transaction is built
    /// and signed — so, unlike a display label, it cannot be wrong without the
    /// transaction being wrong too.
    var transactionType: VSTransactionType { get }
    var wasmPayload: WasmExecuteContractPayload? { get }
    var swap: SwapPayload? { get }
    var approve: ERC20ApprovePayload? { get }
    var signedData: SignData? { get }

    /// Whether opaque signed content decides this transaction, making the flat
    /// fields above descriptive rather than authoritative.
    ///
    /// ⚠️ **A fact both sides can state, which is the whole point.** A co-signer
    /// sees a Cosmos delegate as a `signDirect` SignDoc; the initiator has not
    /// built one yet and holds a `cosmosStakingPayload` instead. Keying the
    /// refusal on `signedData` alone made the two devices disagree — co-signer
    /// `.unknown`, initiator `.transfer` — on a transaction neither of them can
    /// actually read. Each side answers this from what it has, and both refuse
    /// together.
    ///
    /// It says only that the fields cannot be trusted. It never implies WHICH
    /// operation is hiding behind them.
    var hasOpaqueSignedContent: Bool { get }
}

// MARK: - A co-signer's view

extension KeysignPayload: SignedTransactionContent {

    var toAmountRaw: BigInt { toAmount }

    var signedMemo: String? {
        guard let memo, !memo.isEmpty else { return nil }
        return memo
    }

    var transactionType: VSTransactionType { chainSpecific.transactionType }

    var wasmPayload: WasmExecuteContractPayload? { wasmExecuteContractPayload }

    var swap: SwapPayload? { swapPayload }

    var approve: ERC20ApprovePayload? { approvePayload }

    var signedData: SignData? { signData }

    var hasOpaqueSignedContent: Bool { signData != nil }
}

// MARK: - An initiator's view

/// The initiator's transaction seen through the same window as a co-signer's
/// payload, so both are described by one decoder.
///
/// ⚠️ Three members answer `nil` here, and that is a statement about WHEN this
/// is asked rather than an omission. `swap`, `approve` and `signedData` do not
/// exist yet while the Verify screen is up — they are produced during payload
/// construction, some behind network calls. Decoders that need them therefore do
/// not fire on the initiator, which costs nothing today: swaps are verified on
/// `SwapVerifyScreen` and Cosmos staking on `CosmosStakingVerifySummaryView`,
/// and neither asks for a decoded reading. If that ever changes, the fix is to
/// build the payload earlier — not to let this side answer from something the
/// transaction has not committed to.
struct InitiatingTransactionContent: SignedTransactionContent {

    let transaction: SendTransaction

    init(_ transaction: SendTransaction) {
        self.transaction = transaction
    }

    var coin: Coin { transaction.coin }

    var toAddress: String { transaction.toAddress }

    var toAmountRaw: BigInt { transaction.amountInRaw }

    var signedMemo: String? {
        transaction.memo.isEmpty ? nil : transaction.memo
    }

    var transactionType: VSTransactionType { transaction.transactionType }

    var wasmPayload: WasmExecuteContractPayload? { transaction.wasmContractPayload }

    var swap: SwapPayload? { nil }

    var approve: ERC20ApprovePayload? { nil }

    var signedData: SignData? { nil }

    /// The initiator's form of the same fact. It has no SignDoc yet — that is
    /// built from these payloads at signing time — so it reports the intent that
    /// will become one, and refuses in step with the device that receives it.
    var hasOpaqueSignedContent: Bool {
        transaction.cosmosStakingPayload != nil || transaction.solanaStakingPayload != nil
    }
}

// MARK: - Reading the discriminator off the chain-specific case

extension BlockChainSpecific {

    /// The wire transaction type, for the three chains whose specifics carry
    /// one. Everything else has no discriminator to offer and answers
    /// `.unspecified`, which is what an absent proto3 enum reads as anyway.
    var transactionType: VSTransactionType {
        switch self {
        case .THORChain(_, _, _, _, let transactionType):
            return VSTransactionType(rawValue: transactionType) ?? .unspecified
        case .Cosmos(_, _, _, let transactionType, _, _):
            return VSTransactionType(rawValue: transactionType) ?? .unspecified
        case .Ripple(_, _, _, _, let transactionType):
            return VSTransactionType(rawValue: transactionType) ?? .unspecified
        case .UTXO, .Cardano, .Ethereum, .MayaChain, .Solana, .Sui,
             .Polkadot, .Ton, .Tron:
            return .unspecified
        }
    }
}
