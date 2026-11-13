//
//  TonLiquidStakeTransactionViewModel.swift
//  VultisigApp
//

import Foundation
import Combine
import BigInt

@MainActor
final class TonLiquidStakeTransactionViewModel: ObservableObject, Form {
    /// Native TON coin — funds the Tonstakers deposit.
    let coin: Coin
    let vault: Vault

    @Published var validForm: Bool = false

    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    /// TON redeemable per tsTON, or `nil` until read (or when the read fails).
    @Published private(set) var tonPerTsTON: Decimal?
    /// Pool `min_stake` in nanotons when tonapi reports one.
    @Published private(set) var poolMinStake: BigInt?

    /// Smallest deposit value: pool minimum plus the 1 TON deposit fee (2 TON by default).
    var minStake: Decimal {
        toDecimal(Tonstakers.minimumDepositValue(minStake: poolMinStake))
    }

    /// The pool's deposit fee, shown on the form.
    var depositFee: Decimal {
        toDecimal(Tonstakers.depositFee)
    }

    /// tsTON the pool mints for `amount`, net of its fee; `nil` while the rate is unknown.
    func expectedTsTON(for amount: Decimal) -> Decimal? {
        guard let rate = tonPerTsTON, rate > 0 else { return nil }
        let net = amount - depositFee
        return net > 0 ? net / rate : 0
    }

    private func toDecimal(_ nano: BigInt) -> Decimal {
        (Decimal(string: nano.description) ?? 0) / pow(Decimal(10), coin.decimals)
    }

    /// Network fee (TON `defaultFee`) reserved from the spendable balance.
    var feeDecimal: Decimal {
        TonHelper.defaultFee.description.toDecimal() / pow(Decimal(10), coin.decimals)
    }

    var maxStakeableAmount: Decimal {
        let remaining = coin.balanceDecimal - feeDecimal
        return remaining > 0 ? remaining : 0
    }

    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal > feeDecimal
    }

    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
    }

    func onLoad() {
        setupForm()
        Task { await loadPool() }
        amountField.validators.append(AmountBalanceValidator(balance: maxStakeableAmount))
        amountField.validators.append(
            ClosureValidator { [weak self] value in
                guard let self else { return }
                let amount = value.toDecimal()
                // Read live so a pool minimum that arrives after load still applies.
                if amount < self.minStake {
                    throw MinStakeError.belowMinimum(self.minStake, self.coin.chain.ticker)
                }
            }
        )
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, hasSufficientBalanceForFee else { return nil }
        return TonLiquidStakeTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals)
        )
    }

    private func loadPool() async {
        async let info = TonService.shared.getStakingPoolInfo(poolAddress: Tonstakers.poolAddress)
        async let rate = TonService.shared.getTonstakersRate()
        if let minStake = await info?.minStake, minStake > 0 {
            poolMinStake = BigInt(minStake)
        }
        tonPerTsTON = await rate
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
