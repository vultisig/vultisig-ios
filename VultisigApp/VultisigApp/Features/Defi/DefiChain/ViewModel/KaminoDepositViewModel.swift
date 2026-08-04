//
//  KaminoDepositViewModel.swift
//  VultisigApp
//
//  Deposit form for one curated Kamino Earn vault.
//
//  Denominated in the vault's underlying asset, which is what the user holds and
//  what the API's deposit endpoint takes. Shares never appear here — a deposit
//  mints them, but they are staked into the vault's farm and never reach the
//  wallet.
//
//  The form itself only decides *whether* a request may be made. Everything that
//  decides what gets signed happens in `KaminoTransactionPreparer` at continue
//  time, against the transaction the API actually returns.
//

import BigInt
import Combine
import Foundation
import OSLog

@MainActor
final class KaminoDepositViewModel: ObservableObject, Form {

    let vault: Vault
    let descriptor: KaminoVaultDescriptor

    @Published var validForm: Bool = false
    @Published var isLoading = false
    @Published var error: Error?
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    /// The wallet coin the deposit is denominated in — the user's USDC, or their
    /// native SOL for the wrapped-SOL vault. `nil` when the vault has not added
    /// it, which is the one thing the form cannot work around.
    @Published private(set) var depositCoin: Coin?
    /// The most the user may deposit. For a token vault this is the token
    /// balance; for the SOL vault it is the balance less a reserve measured from
    /// the transaction itself (see `KaminoTransactionPreparer`).
    @Published private(set) var availableAmount: Decimal = .zero
    @Published private(set) var vaultInfo: KaminoVaultInfo?

    private(set) lazy var form: [FormField] = [amountField]
    var formCancellable: AnyCancellable?

    private let service: KaminoServiceProtocol
    private let preparer: KaminoDepositPreparing
    private let balanceService: BalanceServiceProtocol
    private let logger = Log.defi.viewModel

    /// The compute-unit price for this whole form session.
    ///
    /// Resolved once and reused: the SOL reserve is measured by simulating a
    /// probe deposit, and the priority fee is part of what that measurement
    /// captures. Re-sampling the price between the probe and the real
    /// transaction would size the reserve against a fee the transaction does not
    /// pay.
    private var unitPrice = KaminoComputeBudget.fallbackUnitPriceMicroLamports

    init(
        vault: Vault,
        descriptor: KaminoVaultDescriptor,
        service: KaminoServiceProtocol = KaminoService(),
        preparer: KaminoDepositPreparing = KaminoTransactionPreparer(),
        balanceService: BalanceServiceProtocol = BalanceService.shared
    ) {
        self.vault = vault
        self.descriptor = descriptor
        self.service = service
        self.preparer = preparer
        self.balanceService = balanceService
        self.depositCoin = Self.resolveDepositCoin(descriptor: descriptor, vault: vault)
    }

    var coinMeta: CoinMeta? {
        depositCoin?.toCoinMeta() ?? descriptor.underlyingCoinMeta
    }

    var ticker: String { coinMeta?.ticker ?? "" }

    /// `true` when the user has no wallet coin for this vault's asset. The form
    /// stays visible so the reason is legible, but nothing can be deposited.
    var isMissingDepositCoin: Bool { depositCoin == nil }

    var missingCoinText: String {
        String(format: "kaminoDepositMissingCoin".localized, ticker)
    }

    /// Vault minimum in human units. `nil` until the vault is hydrated — an
    /// unknown minimum must not read as "no minimum", because the API accepts a
    /// below-minimum deposit and lets it fail on chain.
    var minimumDeposit: Decimal? {
        vaultInfo?.minDeposit.decimalValue
    }

    var minimumDepositText: String {
        guard let vaultInfo else { return "" }
        return String(format: "kaminoDepositMinimum".localized, vaultInfo.minDeposit.apiString, ticker)
    }

    /// Whether this vault's underlying token is wrapped SOL, which the deposit
    /// transaction wraps from the user's native balance. Two things hang off it:
    /// the deposit spends the native coin, and it spends more of it than the
    /// amount.
    var isWrappedSolVault: Bool { descriptor.tokenMint == KaminoVaultRegistry.wrappedSolMint }

    /// The wrapped-SOL vault opens a wSOL account on deposit and never closes
    /// it, so its rent stays locked up until the user withdraws. Disclosed
    /// because it is the user's SOL and it does not come back with this
    /// transaction.
    var showsWrappedSolNotice: Bool { isWrappedSolVault }

    // MARK: - Load

    func onLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let info = try await service.fetchVaultInfo(descriptor: descriptor)
            vaultInfo = info
            amountField.validators.append(
                MinAmountValidator(
                    minimum: info.minDeposit.decimalValue,
                    errorMessage: minimumDepositText
                )
            )
        } catch {
            // Without the vault's own minimum there is no gate — the API builds
            // a below-minimum deposit happily and the chain rejects it after the
            // ceremony — so the form stays unusable rather than guessing. The
            // validation pipeline is deliberately never started.
            logger.error("Kamino vault hydration failed: \(error.localizedDescription, privacy: .public)")
            self.error = error
            return
        }

        setupForm()
        unitPrice = await preparer.resolveUnitPrice()

        if let depositCoin {
            await balanceService.updateBalance(for: depositCoin)
            await resolveAvailableAmount(coin: depositCoin)
        }

        // Installed unconditionally. With no wallet coin, or with a reserve that
        // could not be measured, the available amount is zero — and a form that
        // cannot be completed is the honest outcome, rather than a Continue
        // button that silently does nothing.
        amountField.validators.append(AmountBalanceValidator(balance: availableAmount))
    }

    // MARK: - Continue

    /// What the verify screen needs, built from ONE reading of the amount.
    ///
    /// The two travel together on purpose. Preparing the transaction takes
    /// several network round trips, and the amount field stays editable
    /// throughout — so re-reading it afterwards to build the summary could
    /// describe a different deposit from the one inside the bytes.
    struct DepositHandoff {
        let payload: KeysignPayload
        let transaction: SendTransaction
    }

    /// Builds the payload the verify screen signs and the summary it shows, or
    /// `nil` with `error` set.
    func makeDeposit() async -> DepositHandoff? {
        guard let vaultInfo, let depositCoin else { return nil }
        guard let amount = enteredAmount(), amount.isValidRequestAmount else {
            error = KaminoServiceError.invalidAmount(amountField.value)
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let prepared = try await preparer.prepareDeposit(
                vault: vaultInfo,
                owner: depositCoin.address,
                amount: amount,
                unitPrice: unitPrice
            )
            let payload = try KaminoDepositPayloadFactory.makeDeposit(
                prepared: prepared,
                vaultInfo: vaultInfo,
                amount: amount,
                coin: depositCoin,
                vault: vault
            )
            return DepositHandoff(
                payload: payload,
                transaction: displayTransaction(amount: amount, coin: depositCoin)
            )
        } catch {
            logger.error("Kamino deposit build failed: \(error.localizedDescription, privacy: .public)")
            self.error = error
            return nil
        }
    }

    /// Display-only transaction for the verify summary. The signed bytes come
    /// from the pre-built payload, so this exists purely to name the asset, the
    /// amount and the destination.
    ///
    /// It shows the amount as it was PARSED, not as it was typed. The two can
    /// differ — a stray grouping separator, more precision than the mint has —
    /// and the approver has to be looking at the number that is inside the bytes.
    ///
    /// Rendered in the device's own locale rather than as the POSIX `apiString`.
    /// Everything downstream reads `SendTransaction.amount` back through
    /// `parseInput`, which tries the device locale first: a POSIX `10.123456`
    /// handed to a comma-locale device reads its `.` as a grouping separator and
    /// the summary would show ten million.
    func displayTransaction(amount: KaminoTokenAmount, coin: Coin) -> SendTransaction {
        SendTransaction.empty(coin: coin, vault: vault).with(
            toAddress: descriptor.address,
            amount: amount.decimalValue.formatToDecimal(digits: descriptor.tokenDecimals)
        )
    }

    // MARK: - Amount

    /// The entered amount in the vault's token base units, parsed exactly.
    func enteredAmount() -> KaminoTokenAmount? {
        KaminoAmountInput.tokenAmount(amountField.value, decimals: descriptor.tokenDecimals)
    }

    // MARK: - Private

    /// Resolves what the user may deposit.
    ///
    /// A token deposit spends only the token, so the balance is the ceiling. A
    /// SOL deposit also spends SOL on the transaction — the fee, and rent for
    /// the accounts it creates and does not close — so the ceiling is measured
    /// by preparing and simulating a probe deposit and reading back what the
    /// payer is left with. A failed measurement leaves nothing available rather
    /// than offering a maximum that cannot execute.
    private func resolveAvailableAmount(coin: Coin) async {
        guard let vaultInfo else { return }
        guard isWrappedSolVault else {
            availableAmount = coin.balanceDecimal
            return
        }

        do {
            let lamports = try await preparer.maxNativeDepositLamports(
                vault: vaultInfo,
                owner: coin.address,
                probe: vaultInfo.minDeposit,
                unitPrice: unitPrice
            )
            availableAmount = KaminoTokenAmount(
                baseUnits: lamports,
                decimals: descriptor.tokenDecimals
            ).decimalValue
        } catch {
            logger.error("Kamino SOL reserve measurement failed: \(error.localizedDescription, privacy: .public)")
            availableAmount = .zero
            self.error = error
        }
    }

    /// The wallet coin a deposit into `descriptor` spends.
    ///
    /// The wrapped-SOL vault's underlying mint is wSOL, which the wallet does
    /// not hold as a coin — the deposit transaction wraps native SOL itself — so
    /// that vault resolves to the native coin. Everything else matches on the
    /// pinned mint, never on ticker.
    private static func resolveDepositCoin(descriptor: KaminoVaultDescriptor, vault: Vault) -> Coin? {
        guard descriptor.tokenMint != KaminoVaultRegistry.wrappedSolMint else {
            return vault.coins.first { $0.chain == KaminoVaultRegistry.chain && $0.isNativeToken }
        }
        return vault.coins.first {
            $0.chain == KaminoVaultRegistry.chain
                && !$0.isNativeToken
                && $0.contractAddress == descriptor.tokenMint
        }
    }
}
