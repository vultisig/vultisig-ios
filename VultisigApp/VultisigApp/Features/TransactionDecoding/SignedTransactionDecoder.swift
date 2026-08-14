//
//  SignedTransactionDecoder.swift
//  VultisigApp
//
//  Working out what a transaction is by reading what will be signed, rather
//  than by being told.
//
//  A co-signing device holds only the payload, and for most DeFi operations
//  nothing in it identifies the operation — a Cosmos delegate, a Solana stake
//  and an LP deposit carry no memo at all — so every one of them was announced
//  through the generic send vocabulary. The alternative considered first was to
//  carry a declared kind on the wire; it was dropped because a declaration is
//  not part of the signed bytes and can contradict them at no cost. Everything
//  here derives instead, which is the principle `KeysignPayload.isQbtcClaim`
//  already states for claims: a peer works it out rather than being told.
//
//  ⚠️ **Descriptive only. Nothing on the signing path may consult a
//  `DecodedTransaction`.** A decoder that starts deciding how bytes are built is
//  a worse failure mode than the one this removes.
//
//  ⚠️ **No network access, ever.** Resolving a `.fraction` against a staked
//  position needs an off-chain read; that is a separate enrichment step, so
//  decoding stays pure, synchronous and testable, and a failed read cannot take
//  the verb down with it.
//

import Foundation

/// One reading of a transaction.
protocol TransactionContentDecoder {

    /// The chains whose transactions this decoder speaks for, or `nil` when the
    /// grammar it reads is not a property of any one chain.
    ///
    /// ⚠️ `nil` is not laziness. THORChain's inbound memos are sent FROM the
    /// asset's own chain — an LP add or a `SECURE+` leaves Bitcoin, Ethereum or
    /// Gaia carrying a THORChain memo — so keying that grammar on
    /// `coin.chain == .thorChain` would miss almost every real instance of it.
    /// What identifies those transactions is the memo, not where they start.
    var handles: Set<Chain>? { get }

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction?
}

enum SignedTransactionDecoder {

    /// Consulted in order, first non-`nil` answer wins.
    ///
    /// ⚠️ **MAYAChain before THORChain, and that ordering is load-bearing.**
    /// The two protocols spell `BOND`, `UNBOND` and `LEAVE` identically and put
    /// the node in DIFFERENT fields — `BOND:<node>` against
    /// `BOND:<asset>:<fee>:<node>`. Since the THORChain grammar is chain-agnostic
    /// it would otherwise claim a MAYAChain bond and name the wrong party.
    /// MAYAChain is narrower, so it is asked first.
    static let decoders: [TransactionContentDecoder] = [
        MayaChainTransactionDecoder(),
        THORChainTransactionDecoder(),
        CosmosTransactionDecoder()
    ]

    /// What this transaction is.
    ///
    /// Total, and never invents: anything unreadable comes back `.unknown`
    /// rather than being called a transfer, so screens fall back to what they
    /// showed before instead of asserting something nothing supports.
    static func decode(_ tx: SignedTransactionContent) -> DecodedTransaction {
        for decoder in decoders where decoder.handles?.contains(tx.coin.chain) ?? true {
            if let decoded = decoder.decode(tx) {
                return decoded
            }
        }

        // ⚠️ Only AFTER the grammars, never before.
        //
        // A `SwapPayload` is not proof of a swap. ERC-20 LP adds and `SECURE+`
        // deposits synthesize one purely so the legacy router path can build a
        // `depositWithExpiry`, and their own builders say outright that they are
        // deposits. Asking this first — as an earlier revision did — announced
        // those deposits as swaps on the co-signer while the initiator, which
        // has no synthesized payload yet, still called them transfers. The memo
        // is what the chain reads, so the memo answers first.
        if tx.swap != nil {
            return DecodedTransaction(
                operation: .swap,
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                evidence: .structuredPayload
            )
        }

        if let approve = tx.approve {
            return DecodedTransaction(
                operation: .approve,
                amount: .units(approve.amount, of: .transactionCoin),
                counterparty: .contract(approve.spender),
                evidence: .structuredPayload
            )
        }

        // ⚠️ A SignDoc, a raw Solana transaction or a BOC IS the transaction.
        // While no decoder reads them, `toAmount` and `toAddress` are free to
        // disagree with what will actually be signed — a Cosmos delegate can
        // carry any amount at all in those fields without changing its
        // signature. Refusing to describe it is the only honest answer until the
        // signed-data decoders exist.
        //
        // Asked as a fact BOTH devices can state, not as `signedData != nil`:
        // the initiator has not built its SignDoc yet, so keying on the built
        // artefact made it answer `.transfer` for a transaction the co-signer
        // was already refusing to describe.
        if tx.hasOpaqueSignedContent {
            return .unreadable
        }

        // ⚠️ A contract call is not a send either, whoever's contract it is.
        //
        // No chain decoder claimed this one — it belongs to a protocol none of
        // them speak — but the payload still carries an execute message, and
        // that much IS signed. Naming it a contract call says exactly what is
        // known and nothing more; falling through to `.transfer` would have
        // described an arbitrary contract execution as an ordinary payment.
        if let wasm = tx.wasmPayload {
            return DecodedTransaction(
                operation: .contractCall,
                amount: .unstated,
                counterparty: .contract(wasm.contractAddress),
                evidence: .wasmExecuteMsg
            )
        }

        // A memo nobody parses is not a send. Only a transaction with nothing to
        // say for itself is.
        if tx.signedMemo != nil {
            return .unreadable
        }

        return DecodedTransaction(
            operation: .transfer,
            amount: .units(tx.toAmountRaw, of: .transactionCoin),
            evidence: .structuredPayload
        )
    }
}
