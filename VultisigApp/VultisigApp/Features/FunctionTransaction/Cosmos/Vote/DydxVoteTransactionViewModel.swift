//
//  DydxVoteTransactionViewModel.swift
//  VultisigApp
//
//  dYdX governance vote form view-model: pick a ballot option, type a proposal
//  ID, vote. Both fields are real `FormField`s with real validators, which is
//  the substantive change from the legacy sub-model —
//
//  • Its option check was `selectedMemo.rawValue >= 0`, and `.unspecified` has
//    raw value 0, so the clause was vacuous. An "Unspecified" ballot passed
//    validation, the user paid the fee, and the chain rejected the vote. Here
//    `.unspecified` is not offered by the picker *and* is refused by the
//    option field's validator.
//  • Its proposal ID came off a locale-aware integer field, so a grouped or
//    comma-decimal entry could resolve to a different number than was typed.
//    `ProposalID.parse` reads digits and nothing else.
//

import Combine
import Foundation
import WalletCore

@MainActor
final class DydxVoteTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault

    @Published var validForm: Bool = false

    /// Carries the option's *memo token*, not its display title: the validator
    /// then rejects anything `DydxVoteOption.option(forMemoValue:)` cannot
    /// resolve, which is every unsubmittable option and the pristine empty
    /// state. Validators are attached at construction rather than in
    /// `onLoad()` so there is no window in which the shared pipeline can
    /// validate an unguarded field and publish a valid pristine form.
    @Published var optionField = FormField(
        label: "governanceCastVote".localized,
        validators: [
            ClosureValidator { value in
                guard DydxVoteOption.option(forMemoValue: value) != nil else {
                    throw HelperError.runtimeError("selectVoteOptionError".localized)
                }
            }
        ]
    )

    @Published var proposalIDField = FormField(
        label: "proposalID".localized,
        placeholder: "proposalID".localized,
        validators: [
            ClosureValidator { value in
                guard let proposalID = ProposalID.parse(value), proposalID > 0 else {
                    throw HelperError.runtimeError("invalidProposalIDError".localized)
                }
            }
        ]
    )

    private(set) lazy var form: [FormField] = [optionField, proposalIDField]

    var formCancellable: AnyCancellable?

    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
    }

    /// The ballot options the screen offers. Never contains `.unspecified`.
    let options: [TW_Cosmos_Proto_Message.VoteOption] = DydxVoteOption.selectable

    func onLoad() {
        setupForm()
    }

    /// Commits a ballot option. Ignores an unsubmittable one rather than
    /// writing it: the picker cannot produce one, and an `.unspecified` sitting
    /// in the field is exactly the state the legacy form let through.
    func select(_ option: TW_Cosmos_Proto_Message.VoteOption) {
        guard DydxVoteOption.isSubmittable(option) else { return }
        optionField.value = DydxVoteOption.memoValue(for: option)
    }

    /// The picked ballot option, **derived** from the field rather than stored
    /// beside it.
    ///
    /// A second stored copy would buy nothing and could only ever become a way
    /// for what the screen shows and what the memo carries to disagree — the
    /// field is what the validator and the builder read, so anything written
    /// there wins at signing time regardless of what a stored copy said. One
    /// expression feeds both, so the ballot on screen is the ballot signed.
    var selectedOption: TW_Cosmos_Proto_Message.VoteOption? {
        DydxVoteOption.option(forMemoValue: optionField.rawValue)
    }

    var transactionBuilder: TransactionBuilder? {
        // The fields, not the published `validForm`, decide this turn's
        // submission: the aggregate is republished a run-loop turn late, so a
        // form completed and submitted in the same turn would read the
        // previous turn's answer in both directions.
        validateErrors()
        guard form.allSatisfy({ $0.valid }) else { return nil }

        // `selectedOption` is the same expression the screen renders, so the
        // ballot signed is the ballot shown by construction rather than by two
        // states being kept in step.
        guard let option = selectedOption,
              let proposalID = ProposalID.parse(proposalIDField.rawValue),
              proposalID > 0 else {
            return nil
        }

        return DydxVoteTransactionBuilder(
            coin: coin,
            option: option,
            proposalID: proposalID
        )
    }
}
