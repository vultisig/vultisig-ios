//
//  FunctionCallVote.swift
//  VultisigApp
//
//  DyDx vote memo sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — owns its `selectedMemo` and
//  `proposalID` fields directly and emits the immutable
//  `SendTransaction` via `toSendTransaction(...)`. The matching
//  `VoteFormView` is co-located in this file.
//

import BigInt
import Foundation
import SwiftUI
import VultisigCommonData
import WalletCore

@Observable
@MainActor
final class FunctionCallVote {
    var selectedMemo: TW_Cosmos_Proto_Message.VoteOption = .unspecified
    var proposalID: Int = 0
    var customErrorMessage: String?

    init() {}

    var isTheFormValid: Bool {
        selectedMemo.rawValue >= 0 && proposalID > 0
    }

    var amount: Decimal { .zero }

    var description: String {
        toString()
    }

    func toString() -> String {
        "DYDX_VOTE:\(selectedMemo.description):\(proposalID)"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("VoteDescription", selectedMemo.description)
        dict.set("ProposalId", "\(proposalID)")
        dict.set("memo", toString())
        return dict
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        _ = isFastVault
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .vote,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct VoteFormView: View {
    @Bindable var model: FunctionCallVote

    var body: some View {
        VStack {
            GenericSelectorDropDown(
                items: .constant(TW_Cosmos_Proto_Message.VoteOption.allCases),
                selected: $model.selectedMemo,
                descriptionProvider: { $0.description },
                onSelect: { memo in
                    model.selectedMemo = memo
                }
            )

            StyledIntegerField(
                placeholder: "proposalID".localized,
                value: $model.proposalID,
                format: .number,
                isValid: .constant(true)
            )
        }
    }
}
