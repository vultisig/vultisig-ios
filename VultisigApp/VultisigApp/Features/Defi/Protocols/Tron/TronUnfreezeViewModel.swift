//
//  TronUnfreezeViewModel.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "tron-unfreeze-view-model")

@MainActor
final class TronUnfreezeViewModel: ObservableObject, Form {
    let vault: Vault
    let logic = TronViewLogic()

    @Published var selectedResourceType: TronResourceType = .bandwidth
    @Published var percentageSelected: Double? = 100
    @Published var frozenBandwidthBalance: Decimal = .zero
    @Published var frozenEnergyBalance: Decimal = .zero
    @Published var validForm: Bool = false
    @Published var error: Error?
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    var trxCoin: Coin? {
        TronViewLogic.getTrxCoin(vault: vault)
    }

    /// Frozen balance available to unfreeze for the currently selected resource.
    var availableAmount: Decimal {
        switch selectedResourceType {
        case .bandwidth:
            return frozenBandwidthBalance
        case .energy:
            return frozenEnergyBalance
        }
    }

    init(vault: Vault, frozenBandwidthBalance: Decimal = .zero, frozenEnergyBalance: Decimal = .zero) {
        self.vault = vault
        self.frozenBandwidthBalance = frozenBandwidthBalance
        self.frozenEnergyBalance = frozenEnergyBalance
    }

    func onLoad() {
        setupForm()
        updateValidators()
    }

    func loadData() async {
        do {
            let result = try await logic.fetchData(vault: vault)
            await MainActor.run {
                self.frozenBandwidthBalance = result.frozenBandwidth
                self.frozenEnergyBalance = result.frozenEnergy
                self.error = nil
                self.updateValidators()
            }
        } catch {
            logger.error("Failed to load TRON unfreeze data: \(error.localizedDescription, privacy: .public)")
            await MainActor.run { self.error = error }
        }
    }

    func onResourceChange() {
        updateValidators()
        percentageSelected = 100
    }

    func updateValidators() {
        amountField.validators = [
            RequiredValidator(errorMessage: "emptyAmountField".localized),
            AmountBalanceValidator(balance: availableAmount)
        ]
    }

    /// Builds the TRON unfreeze transaction. Preserves the memo format
    /// (`UNFREEZE:<RESOURCE>`), the staking flag, and send-to-self that
    /// `TronHelper` consumes.
    func makeTransaction() -> SendTransaction? {
        validateErrors()
        guard validForm, let coin = trxCoin else { return nil }

        let amountDecimal = amountField.value.toDecimal()
        guard amountDecimal > 0 else { return nil }

        let memo = "UNFREEZE:\(selectedResourceType.tronResourceString)"

        // Drop the cached account/resource for this address so balances
        // refresh when the user navigates back into the DeFi screens after
        // the unfreeze is broadcast.
        let address = coin.address
        Task { await TronService.shared.invalidateAccountCache(for: address) }

        return SendTransaction.empty(coin: coin, vault: vault).with(
            toAddress: coin.address,
            amount: amountDecimal.description,
            memo: memo,
            isStakingOperation: true
        )
    }
}
