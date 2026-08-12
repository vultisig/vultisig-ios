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
    /// A failure of the action the user asked for — building the deposit. Read
    /// by the screen when `makeDeposit` comes back empty.
    @Published var error: Error?
    /// A failure of the form's own hydration, which is a different thing: the
    /// user did nothing, and there is nothing to correct, so it is rendered
    /// where it happened and paired with a retry rather than thrown as an alert
    /// over an action that was never attempted. Without this the form simply sat
    /// there with a permanently disabled Continue and no explanation.
    @Published private(set) var loadError: Error?
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: KaminoDepositViewModel.baseAmountValidators
    )

    /// What the amount field validates with before the vault is known. Held
    /// apart so a retry can rebuild the list from it — `onLoad` appends, and
    /// running it twice would otherwise install a second minimum and a second
    /// balance check on top of the first.
    private static var baseAmountValidators: [FormFieldValidator] {
        [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    }

    /// The wallet coin the deposit is denominated in — the user's USDC, or their
    /// native SOL for the wrapped-SOL vault. `nil` when the vault has not added
    /// it, which is the one thing the form cannot work around.
    @Published private(set) var depositCoin: Coin?
    /// The most the user may deposit. For a token vault this is the token
    /// balance; for the SOL vault it is the balance less a reserve measured from
    /// the transaction itself (see `KaminoTransactionPreparer`).
    @Published private(set) var availableAmount: Decimal = .zero
    /// The same ceiling in exact base units.
    ///
    /// `availableAmount` is a `Decimal` because the shared amount field renders
    /// one, and rendering rounds. The build path compares against this instead,
    /// so the number the deposit is checked against is the number that was
    /// measured — not a projection of it that came back through a formatter.
    @Published private(set) var availableBaseUnits: BigInt = .zero
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

    /// The hydration failure, in the user's terms, or `nil` when there is none.
    var loadErrorText: String? {
        guard let loadError else { return nil }
        return String(format: "kaminoLoadFailed".localized, loadError.localizedDescription)
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

    /// `true` when no amount the user could type would produce a deposit, so
    /// the Continue button reads as disabled instead of refusing after the tap.
    ///
    /// Deliberately narrow. A below-minimum or over-balance amount is NOT here:
    /// the user can fix it, the field says so, and disabling the button would
    /// remove the tap that reveals the error on an untouched form. What is here
    /// are the states no edit reaches — no wallet coin for this vault's asset, a
    /// vault whose own minimum never loaded (without it there is no gate at all,
    /// since the API builds a below-minimum deposit happily and the chain
    /// rejects it after the ceremony), and a balance that cannot reach the
    /// minimum however it is spent.
    ///
    /// That last one is a real band, not a theoretical one: a wallet holding
    /// less than the vault's minimum has no typeable amount that satisfies both
    /// validators, so leaving the button enabled means the only feedback is a
    /// refusal after the tap. Compared in exact base units, because the ceiling
    /// the build path enforces is `availableBaseUnits` and the `Decimal` beside
    /// it is a rendering of that.
    var isDepositUnavailable: Bool {
        guard let vaultInfo else { return true }
        return isMissingDepositCoin
            || availableAmount <= 0
            || availableBaseUnits < vaultInfo.minDeposit.baseUnits
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

    /// Hydrates the form. Safe to run again, which the retry needs and the
    /// screen's `.task` can cause on its own.
    ///
    /// Everything a previous pass derived is torn down first, so a pass that
    /// fails leaves the form in the same state as one that never ran rather than
    /// in a mixture of the two. That matters most for `vaultInfo` and the
    /// ceiling: keeping them would leave Continue enabled, building against a
    /// hydration this pass could not confirm, underneath a banner saying the
    /// load had failed. `isDepositUnavailable` reads `vaultInfo == nil` as
    /// unavailable, so clearing it is what makes the failure fail closed.
    ///
    /// One pass at a time. The retry lives next to a banner a user can tap
    /// repeatedly, and two passes interleaving would race over the same
    /// published state and clear each other's spinner.
    func onLoad() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        loadError = nil
        vaultInfo = nil
        publishAvailable(KaminoTokenAmount(baseUnits: .zero, decimals: descriptor.tokenDecimals))
        amountField.validators = Self.baseAmountValidators

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
            loadError = error
            return
        }

        setupForm()
        unitPrice = await preparer.resolveUnitPrice()

        if let depositCoin {
            // Skipped for the wrapped-SOL vault, where nothing reads the result.
            // `updateBalance` is two round trips — a price and a `getBalance` —
            // through the same proxy the rest of this load already queues on,
            // and `resolveAvailableAmount` derives that vault's ceiling entirely
            // from the reserve probe rather than from `coin.rawBalance`. The
            // amount field renders `availableAmount` and the ticker; it never
            // reads the coin's stored balance. So on the slowest path the
            // feature has, this was a minute of exposure for a number nothing
            // on the screen shows.
            //
            // Nor does skipping it leave a stale figure anywhere that acts on
            // one: the verify screen refreshes this coin itself before it will
            // sign, and a pre-built payload's balance checks are skipped there
            // anyway because the bytes were already proven by simulation.
            //
            // The token vaults DO read `coin.rawBalance` — it is their entire
            // ceiling — so they still wait for it, and it cannot move off the
            // blocking path without offering a maximum out of a stale balance.
            if !isWrappedSolVault {
                await balanceService.updateBalance(for: depositCoin)
            }
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

        // The bounds are re-enforced here rather than trusted from the form.
        // `FormScreen` does not disable Continue on validation — it cannot, since
        // the tap is what reveals a field's errors — so an amount below the
        // vault's minimum or above the balance reaches this function. Neither can
        // move funds wrongly (the API accepts a below-minimum deposit and the
        // chain then rejects it; an over-balance one fails simulation), but both
        // would cost the user several network round trips and come back as an
        // on-chain failure rather than as the number the form already knows is
        // wrong.
        guard amount.baseUnits >= vaultInfo.minDeposit.baseUnits else {
            error = KaminoDepositError.belowMinimum(
                minimum: vaultInfo.minDeposit.apiString,
                ticker: ticker
            )
            return nil
        }
        guard amount.baseUnits <= availableBaseUnits else {
            error = AmountBalanceValidator.ValidationError.exceedsBalance
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
            let payload = try KaminoKeysignPayloadFactory.makeDeposit(
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
            publishAvailable(KaminoTokenAmount(
                // The stored balance is already in base units, so this is the
                // exact figure rather than a Decimal round trip through it.
                baseUnits: BigInt(coin.rawBalance) ?? .zero,
                decimals: descriptor.tokenDecimals
            ))
            return
        }

        do {
            let lamports = try await preparer.maxNativeDepositLamports(
                vault: vaultInfo,
                owner: coin.address,
                probe: vaultInfo.minDeposit,
                unitPrice: unitPrice
            )
            publishAvailable(KaminoTokenAmount(
                baseUnits: lamports,
                decimals: descriptor.tokenDecimals
            ))
        } catch {
            logger.error("Kamino SOL reserve measurement failed: \(error.localizedDescription, privacy: .public)")
            publishAvailable(KaminoTokenAmount(baseUnits: .zero, decimals: descriptor.tokenDecimals))
            // A load failure, not an action failure: it leaves the form with a
            // zero maximum and a disabled Continue, which is precisely the state
            // that used to be silent.
            loadError = error
        }
    }

    /// Publishes the ceiling in both forms from ONE value, so the number the
    /// form renders and the number the build path enforces can never diverge.
    private func publishAvailable(_ amount: KaminoTokenAmount) {
        availableBaseUnits = amount.baseUnits
        availableAmount = amount.decimalValue
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

/// Why a deposit cannot be made, in the user's terms.
enum KaminoDepositError: Error, LocalizedError, Equatable {
    /// Below the vault's own `minDepositAmount`. The API accepts one of these
    /// and the chain rejects it afterwards, so the refusal has to be ours.
    case belowMinimum(minimum: String, ticker: String)

    var errorDescription: String? {
        switch self {
        case .belowMinimum(let minimum, let ticker):
            return String(format: "kaminoDepositMinimum".localized, minimum, ticker)
        }
    }
}
