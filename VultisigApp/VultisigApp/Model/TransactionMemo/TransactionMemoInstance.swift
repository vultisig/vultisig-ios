//
//  TransactionMemoTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

enum TransactionMemoInstance {
    case bond(TransactionMemoBond)
    case unbond(TransactionMemoUnbond)
    case leave(TransactionMemoLeave)
    case custom(TransactionMemoCustom)
    
    var view: AnyView {
        switch self {
        case .bond(let memo):
            return memo.getView()
        case .unbond(let memo):
            return memo.getView()
        case .leave(let memo):
            return memo.getView()
        case .custom(let memo):
            return memo.getView()
        }
    }
    
    var description: String {
        switch self {
        case .bond(let memo):
            return memo.description
        case .unbond(let memo):
            return memo.description
        case .leave(let memo):
            return memo.description
        case .custom(let memo):
            return memo.description
        }
    }
    
    var amount: Double {
        switch self {
        case .bond(let memo):
            return memo.amount
        case .unbond(let memo):
            return .zero
        case .leave:
            return .zero
        case .custom(let memo):
            return memo.amount
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        switch self {
        case .bond(let memo):
            return memo.toDictionary()
        case .unbond(let memo):
            return memo.toDictionary()
        case .leave(let memo):
            return memo.toDictionary()
        case .custom(let memo):
            return memo.toDictionary()
        }
    }
    
    var isTheFormValid: Bool {
        switch self {
        case .bond(let memo):
            return memo.isTheFormValid
        case .unbond(let memo):
            return memo.isTheFormValid
        case .leave(let memo):
            return memo.isTheFormValid
        case .custom(let memo):
            return memo.isTheFormValid
        }
    }
}
