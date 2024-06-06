//
//  TransactionMemoTransactionMemoAddressable.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

protocol TransactionMemoAddressable: ObservableObject {
    var isTheFormValid: Bool { get set }
    var addressFields: [String: String] { get set }
    func getView() -> AnyView
    func toDictionary() -> ThreadSafeDictionary<String, String>
}
