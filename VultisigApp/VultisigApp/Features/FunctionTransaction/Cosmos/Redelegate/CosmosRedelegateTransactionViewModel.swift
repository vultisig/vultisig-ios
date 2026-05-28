//
//  CosmosRedelegateTransactionViewModel.swift
//  VultisigApp
//
//  Form view-model for the LUNA / LUNC redelegate flow. Source validator
//  is pre-selected from the position card; destination validator is
//  selected via the shared `ValidatorSelectionScreen` (with the source
//  excluded). Pre-flight check against
//  `/cosmos/staking/v1beta1/delegators/{addr}/redelegations` runs in
//  `onLoad()` — if the source validator is under cooldown, `validForm`
//  cannot become true regardless of input, and the screen surfaces the
//  unlock date inline (Spec Risk 4).
//

import Foundation
import Combine
import OSLog

@MainActor
final class CosmosRedelegateTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let validatorSrcAddress: String
    let validatorSrcMoniker: String
    let stakedBalance: Decimal

    @Published var validForm: Bool = false
    @Published var selectedDstValidator: CosmosValidator?
    @Published private(set) var cooldownState: CosmosRedelegationCooldownState = .available
    @Published private(set) var isLoadingCooldown: Bool = false

    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [
            RequiredValidator(errorMessage: "emptyAmountField".localized)
        ]
    )

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    private let stakingService: CosmosStakingServiceProtocol
    private let logger = Logger(
        subsystem: "com.vultisig.app",
        category: "cosmos-redelegate-vm"
    )

    init(
        coin: Coin,
        vault: Vault,
        validatorSrcAddress: String,
        validatorSrcMoniker: String,
        stakedBalance: Decimal,
        stakingService: CosmosStakingServiceProtocol = CosmosStakingService()
    ) {
        self.coin = coin
        self.vault = vault
        self.validatorSrcAddress = validatorSrcAddress
        self.validatorSrcMoniker = validatorSrcMoniker
        self.stakedBalance = stakedBalance
        self.stakingService = stakingService
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: stakedBalance))
        amountField.value = stakedBalance.formatToDecimal(digits: coin.decimals)
        isMaxAmount = true
        Task { await loadCooldown() }
    }

    /// Fetches the user's outstanding redelegations and runs the gate
    /// against the source validator. Failure to load is treated as
    /// "available" rather than "blocked" — the chain is the final
    /// arbiter, so we avoid spurious blocking when the LCD is unreachable.
    /// Worst case the chain rejects post-broadcast (rare for first-time
    /// redelegators); best case the user can proceed offline.
    private func loadCooldown() async {
        isLoadingCooldown = true
        defer { isLoadingCooldown = false }
        do {
            let redelegations = try await stakingService.fetchRedelegations(
                chain: coin.chain,
                address: coin.address
            )
            cooldownState = CosmosRedelegationCooldownGate.evaluate(
                sourceValidator: validatorSrcAddress,
                redelegations: redelegations
            )
        } catch {
            logger.warning(
                "Redelegation cooldown fetch failed; defaulting to available: \(error.localizedDescription, privacy: .public)"
            )
            cooldownState = .available
        }
    }

    /// `Set<String>` used by the picker sheet to filter out the source
    /// from the destination list — you can't redelegate to yourself.
    var excludedDstValidators: Set<String> {
        [validatorSrcAddress]
    }

    /// Localised cooldown blocker — surfaced inline when the source
    /// validator is under a 21-day redelegation cooldown.
    var cooldownBlockedMessage: String? {
        if case .blocked(let unlocksAt) = cooldownState {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return String(
                format: "cosmosStakingRedelegateCooldownBlocked".localized,
                formatter.string(from: unlocksAt)
            )
        }
        return nil
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, let dst = selectedDstValidator else { return nil }
        guard !dst.jailed else { return nil }
        guard case .available = cooldownState else { return nil }
        return CosmosRedelegateTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            sendMaxAmount: isMaxAmount,
            validatorSrcAddress: validatorSrcAddress,
            validatorDstAddress: dst.operatorAddress
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
