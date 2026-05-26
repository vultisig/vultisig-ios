//
//  FunctionCallCosmosSwitch.swift
//  VultisigApp
//
//  COSMOS-to-THORChain SWITCH sub-model. Form-VM rewrite per the
//  FunctionCall sub-model rewrite workstream — owns destination/THOR
//  addresses + amount directly. The matching `CosmosSwitchFormView` is
//  co-located in this file.
//

import BigInt
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-call-cosmos-switch")

/*
 2) COSMOS - FUNCTION: "SWITCH THORCHAIN"

 UI Elements:
 • Address Field: prefilled with the user's THORChain address (manual override allowed)
 • Amount Field: Enter amount to switch

 Action:
 → Send MsgSend from COSMOS to THORChain vault
 → Include memo: SWITCH:<thorAddress>
*/

@Observable
@MainActor
final class FunctionCallCosmosSwitch {
    var amount: Decimal = 0.0
    var destinationAddress: String = ""
    var thorAddress: String = ""

    var destinationAddressError: String?
    var thorAddressError: String?
    var customErrorMessage: String?

    @ObservationIgnored private var loadingTasks: [Task<Void, Never>] = []

    init(coin: Coin, vault: Vault) {
        self.amount = coin.balanceDecimal

        if let thorchainCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
            self.thorAddress = thorchainCoin.address
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.fetchInboundAddress()
        }
        loadingTasks.append(task)
    }

    deinit {
        loadingTasks.forEach { $0.cancel() }
    }

    private func fetchInboundAddress() async {
        let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
        if let match = addresses.first(where: { $0.chain.uppercased() == "GAIA" }) {
            let halted = match.halted
            let globalPaused = match.global_trading_paused
            let chainPaused = match.chain_trading_paused

            if halted || globalPaused || chainPaused {
                logger.warning("Chain is halted or paused. Cannot proceed with switch.")
                return
            }
            destinationAddress = match.address
        }
    }

    var isTheFormValid: Bool {
        amount > 0 &&
        !destinationAddress.isEmpty &&
        FunctionCallAddressValidation.isValidThorMayaTON(thorAddress)
    }

    func handle(destinationAddressResult: AddressResult?) {
        guard let result = destinationAddressResult else { return }
        destinationAddress = result.address
    }

    func handle(thorAddressResult: AddressResult?) {
        guard let result = thorAddressResult else { return }
        thorAddress = result.address
    }

    func balance(for coin: Coin) -> String {
        let balance = coin.balanceDecimal.description
        return String(format: "balanceInParentheses".localized, balance, coin.ticker.uppercased())
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        "SWITCH:\(thorAddress)"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", destinationAddress)
        dict.set("thorchainAddress", thorAddress)
        dict.set("memo", toString())
        return dict
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        SendTransaction.empty(coin: coin, vault: vault).copy(
            toAddress: destinationAddress,
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct CosmosSwitchFormView: View {
    @Bindable var model: FunctionCallCosmosSwitch
    let coin: Coin

    var body: some View {
        VStack {
            AddressTextField(
                address: $model.destinationAddress,
                label: "destinationAddress".localized,
                coin: coin,
                error: $model.destinationAddressError
            ) { result in
                model.handle(destinationAddressResult: result)
            }

            AddressTextField(
                address: $model.thorAddress,
                label: "thorchainAddress".localized,
                coin: coin,
                error: $model.thorAddressError
            ) { result in
                model.handle(thorAddressResult: result)
            }

            StyledFloatingPointField(
                label: "\("amount".localized) \(model.balance(for: coin))",
                placeholder: "enterAmount".localized,
                value: $model.amount,
                isValid: .constant(true)
            )
        }
    }
}
