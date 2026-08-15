//
//  DydxVoteTransactionBuilder.swift
//  VultisigApp
//
//  dYdX governance vote. Two fields, one memo, nothing attached.
//
//  The memo is the whole instruction: `DYDX_VOTE:<option>:<proposalID>` is
//  parsed downstream into the ballot, so a wrong token in it is a vote cast on
//  something other than what the user picked.
//
//  Deliberately not named `VoteTransactionBuilder`. The DeFi tab builds a
//  `QBTC_VOTE` memo from its own governance segment, and the two are not
//  interchangeable — a generic name is an invitation to route QBTC governance
//  through here and sign a dYdX memo.
//

import Foundation
import VultisigCommonData
import WalletCore

struct DydxVoteTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// The ballot. The builder is pure and renders whatever it is given —
    /// including `.unspecified`, which the chain rejects. Refusing that one is
    /// the form's job (`DydxVoteTransactionViewModel.transactionBuilder`
    /// returns nil), and it is pinned there; keeping the builder total is what
    /// lets a test pin the memo for every option value.
    let option: TW_Cosmos_Proto_Message.VoteOption
    /// Cosmos gov proposal IDs are `uint64`.
    let proposalID: UInt64

    /// A vote moves no value: the ballot rides the memo and the deposit itself
    /// is empty. Pinned to the legacy sub-model's zero as a fund-safety
    /// constant — `SendTransaction.amountInRaw` reads this as a human decimal
    /// and multiplies by 10^decimals, and DYDX has 18 of them.
    let amount: String = "0"
    let sendMaxAmount: Bool = false

    var memo: String { "DYDX_VOTE:\(DydxVoteOption.memoValue(for: option)):\(proposalID)" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("VoteDescription", DydxVoteOption.memoValue(for: option))
        dict.set("ProposalId", "\(proposalID)")
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType { .vote }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// Empty: the vote is addressed by its memo, not by a recipient.
    var toAddress: String { .empty }
}
