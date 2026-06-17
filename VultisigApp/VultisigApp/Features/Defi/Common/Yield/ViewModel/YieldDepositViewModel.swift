//
//  YieldDepositViewModel.swift
//  VultisigApp
//

import Foundation
import Combine
import BigInt

/// Deposit form for a yield vault. Produces ONE deposit payload that internally
/// bundles the USDC approve (when the allowance is short) so a first-time deposit
/// is a single keysign ceremony signing approve→deposit. The prebuilt payload is
/// routed through the shared verify pipeline.
@MainActor
final class YieldDepositViewModel: ObservableObject, Form {
    let vault: Vault
    let provider: DefiYieldProvider

    @Published var validForm: Bool = false
    @Published var isLoading = false
    @Published var error: Error?
    @Published private(set) var usdcCoin: Coin?
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    /// 7d-net APY for the provider, expressed as a PERCENT (e.g. `12.5` ⇒ 12.5%),
    /// fetched once on load. `nil` until fetched or when the read fails — the
    /// preview then renders `--`.
    @Published private(set) var apyPercent: Decimal?
    /// Re-published whenever the entered amount changes so the preview rows track
    /// the keystroke. Driven by `amountField.$value`.
    @Published private(set) var enteredAmount: Decimal?

    private(set) lazy var form: [FormField] = [amountField]
    var formCancellable: AnyCancellable?
    private var amountCancellable: AnyCancellable?

    init(vault: Vault, providerID: DefiYieldProviderID) {
        self.vault = vault
        self.provider = DefiYieldProviderFactory.make(providerID)
        fetchUsdcCoin()
    }

    var availableAmount: Decimal {
        usdcCoin?.balanceDecimal ?? 0
    }

    var coinMeta: CoinMeta? {
        usdcCoin?.toCoinMeta()
    }

    /// Product minimum deposit in human units (e.g. 100 USDC for Noon). `0` ⇒ no
    /// minimum.
    var minDepositAmount: Decimal {
        provider.minDepositAmount
    }

    var hasMinimumDeposit: Bool {
        minDepositAmount > 0
    }

    /// Localized "Minimum deposit is 100 USDC." copy for the info banner / error.
    var minimumDepositText: String {
        String(format: "yieldMinimumDeposit".localized, minimumDepositDisplay, depositTicker)
    }

    private var depositTicker: String {
        usdcCoin?.ticker ?? "USDC"
    }

    /// The minimum rendered without trailing zeros (100, not 100.0000).
    private var minimumDepositDisplay: String {
        NSDecimalNumber(decimal: minDepositAmount).stringValue
    }

    // MARK: - Estimated-yield preview

    /// Pure projection of the entered amount over a month/year at the current
    /// APY, or `nil` when either input is missing/non-positive.
    private var estimate: YieldEstimate? {
        YieldEstimate.make(amount: enteredAmount, apyPercent: apyPercent)
    }

    /// Whether the estimated-yield rows should render: a positive amount and a
    /// known APY. Otherwise the deposit screen hides the preview entirely.
    var showsYieldPreview: Bool {
        estimate != nil
    }

    /// Formatted "<value> USDC" monthly estimate, or `--` when unavailable.
    var estimatedMonthlyText: String {
        format(yield: estimate?.monthly)
    }

    /// Formatted "<value> USDC" yearly estimate, or `--` when unavailable.
    var estimatedYearlyText: String {
        format(yield: estimate?.yearly)
    }

    private func format(yield value: Decimal?) -> String {
        guard let value else { return "--" }
        return AmountFormatter.formatCryptoAmount(value: value, ticker: depositTicker)
    }

    func onLoad() async {
        isLoading = true
        defer { isLoading = false }

        observeAmount()
        await fetchApy()

        guard let usdcCoin else { return }
        await BalanceService.shared.updateBalance(for: usdcCoin)

        if hasMinimumDeposit {
            amountField.validators.append(
                MinAmountValidator(minimum: minDepositAmount, errorMessage: minimumDepositText)
            )
        }
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: usdcCoin.balanceDecimal))
    }

    /// Mirrors the entered amount into `enteredAmount` so the preview recomputes
    /// as the user types. Kept on its own cancellable so it doesn't disturb the
    /// `Form` validation pipeline (`formCancellable`).
    private func observeAmount() {
        enteredAmount = Decimal(string: amountField.value)
        amountCancellable = amountField.$value
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.enteredAmount = Decimal(string: value)
            }
    }

    /// Loads the provider's 7d-net APY (a percent). A failed read leaves the
    /// preview showing `--` rather than surfacing an error on the deposit form.
    private func fetchApy() async {
        apyPercent = try? await provider.apy(vault: vault)
    }

    private func fetchUsdcCoin() {
        usdcCoin = vault.coins.first { $0.chain == provider.chain && $0.ticker == "USDC" }
    }

    /// `nil` ⇒ the entered amount doesn't convert to integer base units; the
    /// caller must block payload construction rather than fall through to a
    /// zero-amount transaction.
    private var amountBaseUnits: BigInt? {
        guard let amount = Decimal(string: amountField.value) else { return nil }
        return YieldAmount.baseUnits(amount, decimals: provider.assetDecimals)
    }

    /// Builds the single deposit payload. The provider bundles the USDC approve
    /// into it when the allowance is short, so the caller routes once to verify
    /// and the ceremony signs approve→deposit (or just deposit when allowance is
    /// sufficient).
    func makeDepositPayload() async -> KeysignPayload? {
        guard let amount = amountBaseUnits, amount > 0 else {
            if !amountField.value.isEmpty {
                error = DefiYieldError.invalidAmount
            }
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            return try await provider.buildDepositPayload(vault: vault, amount: amount)
        } catch {
            self.error = error
            return nil
        }
    }

    func displayTransaction() -> SendTransaction? {
        guard let usdcCoin else { return nil }
        return SendTransaction.empty(coin: usdcCoin, vault: vault).with(
            toAddress: provider.depositRecipient,
            amount: amountField.value
        )
    }
}
