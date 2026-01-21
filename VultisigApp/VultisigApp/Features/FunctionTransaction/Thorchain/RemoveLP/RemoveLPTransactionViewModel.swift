//
//  RemoveLPTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class RemoveLPTransactionViewModel: ObservableObject {
    let coin: Coin
    let vault: Vault
    let position: LPPosition

    var dustAmount: Decimal {
        switch coin.chain {
        case .thorChain:
            0.02
        case .mayaChain:
            0
        default:
            0
        }
    }

    @Published var percentageSelected: Double? = 100
    @Published var feeError: String? = nil
    @Published var validForm = false

    init(
        coin: Coin,
        vault: Vault,
        position: LPPosition
    ) {
        self.coin = coin
        self.vault = vault
        self.position = position
    }

    var transactionBuilder: TransactionBuilder? {
        guard validForm, let poolName = position.poolName else { return nil }
        return RemoveLPTransactionBuilder(
            coin: coin,
            amount: dustAmount.formatToDecimal(digits: coin.decimals),
            poolName: poolName,
            poolUnits: position.poolUnits ?? .empty,
            percentage: percentageSelected ?? 100,
            sendMaxAmount: false
        )
    }

    func onLoad() {
        if coin.balanceDecimal < dustAmount {
            feeError = String(
                format: "removeLPDustAmountError".localized,
                AmountFormatter.formatCryptoAmount(value: dustAmount, coin: coin.toCoinMeta())
            )
            validForm = false
        } else {
            validForm = true
        }
    }
}
