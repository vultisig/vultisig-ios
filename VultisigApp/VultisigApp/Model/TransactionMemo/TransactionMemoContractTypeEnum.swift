//
//  TransactionMemoContractTypeEnum.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine


enum TransactionMemoContractType: String, CaseIterable, Identifiable {
    case thorChainMessageDeposit
    var id: String { self.rawValue }

    func getDescription(for coin: Coin) -> String {
        switch self {
        case .thorChainMessageDeposit:
            return "\(coin.chain.name) message deposit"
        }
    }
}
