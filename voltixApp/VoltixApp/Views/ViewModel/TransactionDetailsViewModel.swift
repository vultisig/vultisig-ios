//
//  TransactionDetailsViewModel.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 13/02/2024.
//

import Foundation
class TransactionDetailsViewModel: ObservableObject, Hashable {
    
    
    static func == (lhs: TransactionDetailsViewModel, rhs: TransactionDetailsViewModel) -> Bool {
        // Implement equality based on relevant properties
        return true
    }
    
    func hash(into hasher: inout Hasher) {
        // Add properties to the hasher
    }
    
    @Published var fromAddress: String = "18cBEMRxXHqzWWCxZNtU91F5sbUNKhL5PX"
    @Published var toAddress: String = ""
    @Published var amount: String = ""
    @Published var memo: String = ""
    @Published var gas: String = ""
}
