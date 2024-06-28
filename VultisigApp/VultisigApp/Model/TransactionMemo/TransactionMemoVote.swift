//
//  TransactionMemoVote.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/05/24.
//

import SwiftUI
import Foundation
import Combine
import WalletCore

class TransactionMemoVote: TransactionMemoAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = false
    @Published var selectedMemo: TW_Cosmos_Proto_Message.VoteOption
    
    // Internal
    private var cancellables = Set<AnyCancellable>()
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {
        self.selectedMemo = .unspecified
        setupValidation()
    }
    
    init(selectedMemo: TW_Cosmos_Proto_Message.VoteOption) {
        self.selectedMemo = selectedMemo
        setupValidation()
    }
    
    private func setupValidation() {
        // Implement any validation logic if needed
        // For now, assume form is valid if there's a selected memo
        $selectedMemo
            .map { $0 != .unspecified }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return String(selectedMemo.rawValue)
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
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
        })
    }
}

// Extend TW_Cosmos_Proto_Message.VoteOption to conform to Identifiable and Equatable
extension TW_Cosmos_Proto_Message.VoteOption: Identifiable, Equatable, CaseIterable {
    public var id: Int {
        return self.rawValue
    }
    
    public var description: String {
        switch self {
        case .unspecified:
            return "Unspecified"
        case .yes:
            return "Yes"
        case .abstain:
            return "Abstain"
        case .no:
            return "No"
        case .noWithVeto:
            return "No with Veto"
        case .UNRECOGNIZED(let value):
            return "Unrecognized (\(value))"
        @unknown default:
            return "Unknown"
        }
    }
}
