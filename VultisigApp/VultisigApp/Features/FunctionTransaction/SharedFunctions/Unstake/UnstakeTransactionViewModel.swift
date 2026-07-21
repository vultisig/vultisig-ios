//
//  UnstakeTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "unstake-transaction-view-model")

final class UnstakeTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let isAutocompound: Bool
    let availableToUnstake: Decimal?

    @Published var percentageSelected: Double? = 100
    @Published var availableAmount: Decimal = 0
    var autocompoundBalance: Decimal = 0
    @Published var validForm: Bool = false
    @Published var amountField = FormField(label: "amount".localized)

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        amountField
    ]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(coin: Coin, vault: Vault, isAutocompound: Bool, availableToUnstake: Decimal? = nil) {
        self.coin = coin
        self.vault = vault
        self.isAutocompound = isAutocompound
        self.availableToUnstake = availableToUnstake
    }

    func onLoad() {
        setupForm()
        availableAmount = availableToUnstake ?? coin.stakedBalanceDecimal
        setupAmountField()

        if isAutocompound {
            Task { @MainActor in
                await fetchAutocompoundBalance()
                guard receiptBalanceIsAvailableAmount else { return }
                self.availableAmount = autocompoundBalance
                self.setupAmountField()
            }
        }
    }

    /// Whether the auto-compound receipt balance is also the amount shown to the
    /// user. True for TCY and bRUNE, whose staked cards render receipt units
    /// directly. RUJI's compounded card renders the RUJI-denominated value of the
    /// receipt, so its ceiling stays the amount the card was showing and the
    /// receipt balance is used only to size the redeemed shares — otherwise the
    /// sheet would offer a smaller maximum than the card it was opened from.
    private var receiptBalanceIsAvailableAmount: Bool {
        coin.ticker.uppercased() != "RUJI"
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }

        switch coin.ticker.uppercased() {
        case "TCY":
            return TCYUnstakeTransactionBuilder(
                coin: coin,
                percentage: Int(percentageSelected ?? percentageFromAmount),
                autoCompoundAmount: autocompoundBalance,
                sendMaxAmount: isMaxAmount,
                isAutoCompound: isAutocompound
            )
        case "BRUNE":
            return BRUNEUnstakeTransactionBuilder(
                coin: coin,
                percentage: Int(percentageSelected ?? percentageFromAmount),
                autoCompoundAmount: autocompoundBalance,
                sendMaxAmount: isMaxAmount
            )
        case "RUJI":
            // RUJI's two positions unstake through completely different messages:
            // the auto-compounding one redeems sRUJI receipt shares with
            // `liquid.unbond`, the bonded one withdraws RUJI with
            // `account.withdraw`. Both arrive here on the RUJI coin because the
            // compounded card maps sRUJI back to its bond coin.
            if isAutocompound {
                // The redemption spends receipt shares, and unlike TCY/bRUNE the
                // share balance is not what bounds the amount field — so nothing
                // else stops a zero here. A zero means the read is still in flight,
                // failed, or the position is empty; all three would build a wasm
                // execute carrying no funds.
                guard autocompoundBalance > 0 else { return nil }
                return RUJILiquidUnbondTransactionBuilder(
                    coin: coin,
                    percentage: Int(percentageSelected ?? percentageFromAmount),
                    receiptShares: autocompoundBalance,
                    sendMaxAmount: isMaxAmount
                )
            }
            return RUJIUnstakeTransactionBuilder(
                coin: coin,
                amount: amountField.value,
                sendMaxAmount: isMaxAmount
            )

        case "CACAO":
            return CacaoUnstakeTransactionBuilder(
                coin: coin,
                bps: Int(percentageSelected ?? percentageFromAmount) * 100,
            )
        default:
            return nil
        }
    }

    var percentageFromAmount: Double {
        guard availableAmount != .zero else { return 0 }
        let decimal = (amountField.value.toDecimal() / availableAmount) * 100.0
        return (decimal as NSDecimalNumber).doubleValue
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }

    func setupAmountField() {
        self.amountField.validators = [
            AmountBalanceValidator(balance: self.availableAmount)
        ]
        self.percentageSelected = 100
        self.isMaxAmount = true
    }

    func fetchAutocompoundBalance() async {
        switch coin.ticker.uppercased() {
        case "TCY":
            let amount: Decimal
            do {
                amount = try await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: coin.address)
            } catch {
                logger.error("Failed to fetch TCY autocompound balance: \(error.localizedDescription, privacy: .private)")
                amount = .zero
            }
            self.autocompoundBalance = coin.valueWithDecimals(value: amount)
        case "BRUNE":
            let amount: Decimal
            do {
                amount = try await ThorchainService.shared.fetchBRuneAutoCompoundAmount(address: coin.address)
            } catch {
                logger.error("Failed to fetch ybRUNE autocompound balance: \(error.localizedDescription, privacy: .private)")
                amount = .zero
            }
            self.autocompoundBalance = coin.valueWithDecimals(value: amount)
        case "RUJI":
            // The sRUJI receipt share balance — what `liquid.unbond` spends. Not a
            // display value: shares are worth more than 1 RUJI each and drift
            // further apart as the pool compounds.
            let amount: Decimal
            do {
                amount = try await ThorchainService.shared.fetchRujiStakingReceiptAmount(address: coin.address)
            } catch {
                logger.error("Failed to fetch sRUJI receipt balance: \(error.localizedDescription, privacy: .private)")
                amount = .zero
            }
            self.autocompoundBalance = coin.valueWithDecimals(value: amount)
        default:
            break
        }
    }
}
