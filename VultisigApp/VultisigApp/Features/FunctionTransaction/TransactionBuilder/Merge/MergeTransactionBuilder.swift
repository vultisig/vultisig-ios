//
//  MergeTransactionBuilder.swift
//  VultisigApp
//
//  Rujira MERGE: deposit a mergeable THORChain token into that token's own
//  merge contract. Three values decide where the funds land — the memo, the
//  contract address and the amount — and all three follow the selected token.
//

import VultisigCommonData

struct MergeTransactionBuilder: TransactionBuilder {
    /// The merge token itself, not THORChain's native asset: the deposit is
    /// funded from this coin's balance and denominated in its decimals.
    let coin: Coin
    /// The catalog denom **uppercased** (`THOR.KUJI`). Part of the wire format:
    /// the legacy dropdown stored the uppercased denom and the memo carried it
    /// verbatim.
    let denom: String
    /// The merge contract for `denom`. A `MsgDeposit` here is addressed by the
    /// recipient, unlike the node memos, so an empty value would send the
    /// funds nowhere.
    let contractAddress: String
    let amount: String

    let sendMaxAmount: Bool = false

    /// Pinned to the legacy `toString()`: lowercase `merge:`, uppercase denom.
    /// THORChain's signer re-lowercases this to derive the deposited denom, but
    /// the memo itself travels on the transaction — a memo the network does not
    /// recognise is a silently failed merge, not a rejected one.
    var memo: String { "merge:\(denom)" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", contractAddress)
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .thorMerge }

    /// `.thorMerge` builds its own `WasmExecuteContractGeneric` from the memo,
    /// the recipient and the amount, so there is no payload to carry here —
    /// see `buildThorchainWasmGenericMessage`.
    var wasmContractPayload: WasmExecuteContractPayload? { nil }

    var toAddress: String { contractAddress }
}
