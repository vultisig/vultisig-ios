//
//  UnmergeTransactionBuilder.swift
//  VultisigApp
//
//  THORChain RUJI UNMERGE — "Withdraw RUJI". A wasm execute against the merge
//  contract of one merged token, withdrawing a number of merge *shares*.
//
//  The memo is not a label here: `THORChainHelper` builds the wasm message by
//  re-parsing the share count out of the memo string
//  (`{"withdraw":{"share_amount":"…"}}`) and attaches no coins at all. The memo
//  is therefore the only thing on this transaction that carries value, which is
//  why `shares` is a raw `BigInt` from the form to the string and why the
//  attached amount is a constant.
//

import BigInt
import Foundation
import VultisigCommonData

struct UnmergeTransactionBuilder: TransactionBuilder {
    /// The asset the transaction is *signed on*. Display and fee resolution
    /// only: the wasm message names the contract, not the coin, and every
    /// THORChain coin shares one address. The view-model passes the merged
    /// token when the vault holds it — as the legacy screen's coin binding did
    /// — so the verify screen and the history entry still name the token being
    /// withdrawn.
    let coin: Coin
    /// The merge denom, e.g. `thor.kuji`. Lowercased into the memo: the
    /// contract's denoms are lowercase, and the signing path lowercases the
    /// whole memo before parsing it, so an uppercase denom here would produce a
    /// memo that no longer round-trips to what the user picked.
    let denom: String
    /// The token's `wasmContractAddress`. Non-optional on purpose: a merge
    /// token with no known contract cannot be unmerged, so it never reaches a
    /// builder rather than being caught by a runtime guard.
    let contractAddress: String
    /// Share count in 1e8 base units — the exact integer the contract acts on.
    let shares: BigInt

    /// UNMERGE moves no value through the transaction: the wasm execute carries
    /// an empty `coins` array and the contract returns the merged tokens on its
    /// own. Pinned to zero as a fund-safety constant, the same way LEAVE and
    /// REBOND pin theirs.
    ///
    /// The legacy sub-model attached the human share count instead. The chain
    /// never read it — the message ignores `toAmount` — but the verify screen
    /// does, and presents it as "you're sending N <ticker>": a count of *shares*
    /// labelled with the *token*'s ticker, two units that are not the same and
    /// drift further apart as the pool earns. Zero is what the message actually
    /// moves, and is what every other memo-only THORChain function call on this
    /// verify screen already shows.
    let amount: String = "0"
    let sendMaxAmount: Bool = false

    var memo: String { "unmerge:\(denom.lowercased()):\(shares.description)" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", contractAddress)
        dict.set("selectedToken", denom.uppercased())
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .thorUnmerge }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// The merge contract. `THORChainHelper` reads it straight into the wasm
    /// message's `contractAddress`, so an empty value would sign a message
    /// addressed to nobody.
    var toAddress: String { contractAddress }
}
