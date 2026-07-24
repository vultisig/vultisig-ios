//
//  DepositViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI
import BigInt
import OSLog
import WalletCore
import Mediator

@MainActor
class FunctionCallViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isValidAddress = false
    @Published var isValidForm = true
    @Published var showAlert = false
    @Published var priceRate = 0.0
    @Published var coinBalance: String = "0"
    @Published var errorMessage = ""
    @Published var hash: String? = nil
    @Published var approveHash: String? = nil

    let blockchainService = BlockChainService.shared
    private let fastVaultService = FastVaultService.shared

    private let mediator = Mediator.shared

    let logger = Logger(subsystem: "deposit-input-details", category: "deposity")

    /// The fiat figure printed beside the crypto fee row.
    ///
    /// ⚠️ Priced off the SAME figure that row is, via `SendCryptoLogic.displayFee`.
    /// This read `tx.gas` unconditionally, which on an EVM function call values
    /// a gwei gas PRICE as though it were the whole fee: a limit-order cancel
    /// costing ~0.00016 ETH rendered as `US$0.00` directly under the crypto
    /// amount that said otherwise.
    func feesInReadable(tx: SendTransaction, vault: Vault) -> String {
        guard let nativeCoin = vault.nativeCoin(for: tx.coin) else { return .empty }
        let fee = nativeCoin.decimal(
            for: SendCryptoLogic.displayFee(coin: tx.coin, gas: tx.gas, fee: tx.fee)
        )
        return RateProvider.shared.fiatBalanceString(value: fee, coin: nativeCoin)
    }

    func memoDictionary(for txDict: [String: String]) -> [String: String] {
        guard !txDict.isEmpty else {
            return [String: String]()
        }

        var dict = [String: String]()
        for (key, value) in txDict {
            guard !value.isEmpty, value != "0", value != "0.0" else { continue }
            dict[key.toFormattedTitleCase()] = value
        }

        return dict
    }

}
