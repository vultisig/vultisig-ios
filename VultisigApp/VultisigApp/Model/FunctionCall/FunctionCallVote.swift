//
//  FunctionCallVote.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/05/24.
//

import SwiftUI
import Foundation
import Combine
import WalletCore

class FunctionCallVote: FunctionCallAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = true
    @Published var customErrorMessage: String? = nil
    @Published var selectedMemo: TW_Cosmos_Proto_Message.VoteOption
    @Published var proposalID: Int = 0

    private var cancellables = Set<AnyCancellable>()

    var addressFields: [String: String] {
        get { [:] }
        set { }
    }

    required init() {
        self.selectedMemo = .unspecified
        setupValidation()
    }

    init(selectedMemo: TW_Cosmos_Proto_Message.VoteOption, proposalID: Int = 0) {
        self.selectedMemo = selectedMemo
        self.proposalID = proposalID
        setupValidation()
    }

    private func setupValidation() {
        $selectedMemo
            .combineLatest($proposalID)
            .map { memo, proposalID in
                memo.rawValue >= 0 && proposalID > 0
            }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        return "DYDX_VOTE:\(selectedMemo.description):\(proposalID)"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("VoteDescription", selectedMemo.description)
        dict.set("ProposalId", "\(proposalID)")
        dict.set("memo", self.toString())
        return dict
    }

    func getView() -> AnyView {
        AnyView(VStack {
            GenericSelectorDropDown(
                items: .constant(TW_Cosmos_Proto_Message.VoteOption.allCases),
                selected: Binding(
                    get: { self.selectedMemo },
                    set: { self.selectedMemo = $0 }
                ),
                descriptionProvider: { $0.description },
                onSelect: { memo in
                    self.selectedMemo = memo
                }
            )

            StyledIntegerField(
                placeholder: NSLocalizedString("proposalID", comment: "Proposal ID placeholder"),
                value: Binding(
                    get: { self.proposalID },
                    set: { self.proposalID = $0 }
                ),
                format: .number,
                isValid: .constant(true)
            )
        })
    }
}
