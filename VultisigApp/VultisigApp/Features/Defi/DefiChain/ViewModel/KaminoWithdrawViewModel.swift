//
//  KaminoWithdrawViewModel.swift
//  VultisigApp
//
//  Withdraw form for one curated Kamino Earn vault.
//
//  Denominated in the vault's underlying asset, which is what the user thinks in
//  and what the position card shows. The API is not: `POST /ktx/kvault/withdraw`
//  takes SHARES, the inverse of deposit's units. (Its published
//  `minWithdrawAmount` is a token figure, though — see
//  `KaminoVaultInfo.minWithdraw`.) Every conversion between the two lives
//  in `KaminoWithdrawMath` so the gate, the maximum and the amount actually sent
//  cannot disagree.
//
//  One thing this form refuses to do, and it is the point of it: it never
//  converts a 100% withdraw. The API silently rewrites a withdraw at or above
//  the user's share balance to `u64::MAX`, which means withdraw everything, so a
//  maximum that round-tripped through the asset and back could turn a partial
//  exit into a full one over a single base unit. `KaminoSharePosition.spendable`
//  is where the maximum comes from and why it stops one base unit short of an
//  exactly-representable balance.
//
//  Farm-staked shares ARE withdrawable. Releasing them from the farm is two more
//  instructions ahead of the vault withdraw, both of them in the validator's
//  template, and how many shares to release is arithmetic on the position split
//  — which is why the form hands `KaminoWithdrawRequest` down rather than a bare
//  share count.
//

import BigInt
import Combine
import Foundation
import OSLog

@MainActor
final class KaminoWithdrawViewModel: ObservableObject, Form {

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

    /// The wallet coin the withdraw settles into — the user's USDC, or their
    /// native SOL for the wrapped-SOL vault, whose token account the withdraw
    /// closes and unwraps.
    @Published private(set) var withdrawCoin: Coin?
    /// The most the user may withdraw, in the underlying asset: the value of
    /// their withdrawable shares at the current rate, truncated.
    @Published private(set) var availableAmount: Decimal = .zero
    @Published private(set) var vaultInfo: KaminoVaultInfo?
    /// What the user's position allows. `nil` until it has been read.
    @Published private(set) var eligibility: KaminoWithdrawEligibility?

    private(set) lazy var form: [FormField] = [amountField]
    var formCancellable: AnyCancellable?

    private let service: KaminoServiceProtocol
    private let preparer: KaminoWithdrawPreparing
    private let logger = Log.defi.viewModel

    /// The exact share figure a full withdraw sends, and the split it is held
    /// in. Read once, at load, and never recomputed from an asset amount.
    private var held: KaminoWithdrawableShares?
    /// The asset value of `held.maximum`, which is both the form's ceiling and
    /// the threshold above which a request means "everything".
    private var maximumTokens: KaminoTokenAmount?

    /// The compute-unit price for this whole form session, resolved once. Pinned
    /// for the same reason the deposit form pins it: a re-sample between
    /// preparing and sending would price the transaction differently from the
    /// one the user was shown.
    private var unitPrice = KaminoComputeBudget.fallbackUnitPriceMicroLamports

    init(
        vault: Vault,
        descriptor: KaminoVaultDescriptor,
        service: KaminoServiceProtocol = KaminoService(),
        preparer: KaminoWithdrawPreparing = KaminoTransactionPreparer()
    ) {
        self.vault = vault
        self.descriptor = descriptor
        self.service = service
        self.preparer = preparer
        self.withdrawCoin = Self.resolveWithdrawCoin(descriptor: descriptor, vault: vault)
    }

    var coinMeta: CoinMeta? {
        withdrawCoin?.toCoinMeta() ?? descriptor.underlyingCoinMeta
    }

    var ticker: String { coinMeta?.ticker ?? "" }

    /// `true` when the user has no wallet coin for this vault's asset. The
    /// withdraw would settle into an account the app cannot name or display.
    var isMissingWithdrawCoin: Bool { withdrawCoin == nil }

    var missingCoinText: String {
        String(format: "kaminoWithdrawMissingCoin".localized, ticker)
    }

    /// The reason this form cannot be used, or `nil` when it can.
    ///
    /// Rendered as a banner rather than an alert: both remaining cases are facts
    /// about the position rather than errors the user caused.
    var unavailableReason: KaminoWithdrawError? {
        switch eligibility {
        case .empty?:
            return .nothingToWithdraw
        case .unreadable?:
            return .positionUnreadable
        case .withdrawable?, nil:
            return nil
        }
    }

    /// The vault's minimum expressed in the asset the form is denominated in.
    /// `nil` until the vault and the position have both been read — the rate is
    /// needed to convert it at all.
    ///
    /// Capped at the form's own maximum when the position clears the minimum in
    /// SHARES. The two conversions round in opposite directions on purpose — the
    /// minimum away from the user, the maximum toward them — so a position
    /// sitting within a base unit of the minimum can render a minimum one unit
    /// above its own balance. Withdrawing is possible there (Max sends the exact
    /// share balance, never a figure converted back out of the asset), so a
    /// minimum above the maximum would be the display contradicting a button
    /// that works. Where the position genuinely holds less than the minimum the
    /// cap does not apply and the real figure stands, because that user needs to
    /// see what they are short of.
    var minimumWithdraw: KaminoTokenAmount? {
        guard let vaultInfo else { return nil }
        guard let minimum = KaminoWithdrawMath.minimumTokens(
            minimumShares: vaultInfo.minWithdraw,
            tokensPerShare: vaultInfo.tokensPerShare,
            tokenDecimals: descriptor.tokenDecimals
        ) else { return nil }

        guard let held, held.maximum.baseUnits >= vaultInfo.minWithdraw.baseUnits,
              let maximumTokens, maximumTokens.baseUnits < minimum.baseUnits
        else { return minimum }
        return maximumTokens
    }

    var minimumWithdrawText: String {
        guard let minimum = minimumWithdraw else { return "" }
        return String(format: "kaminoWithdrawMinimum".localized, minimum.apiString, ticker)
    }

    /// Whether the vault can settle the amount currently entered out of the
    /// balance it holds liquid.
    ///
    /// A normal state to render, not an exception: the measured buffer is 0.36%
    /// of the Steakhouse vault and 0.04% of the Allez vault, so most withdraws
    /// of any size land here.
    var liquidity: KaminoWithdrawLiquidity {
        guard let requested = enteredAmount() else { return .instant }
        return KaminoWithdrawLiquidity.resolve(
            requested: requested,
            available: vaultInfo?.tokensAvailable
        )
    }

    var limitedLiquidityText: String? {
        guard let available = liquidity.availableTokens else { return nil }
        return String(format: "kaminoWithdrawLimitedLiquidity".localized, available.apiString, ticker)
    }

    // MARK: - Load

    func onLoad() async {
        isLoading = true
        defer { isLoading = false }

        let info: KaminoVaultInfo
        do {
            info = try await service.fetchVaultInfo(descriptor: descriptor)
            vaultInfo = info
        } catch {
            // Without the vault's own rate there is no way to turn an asset
            // amount into shares at all, so the form stays unusable rather than
            // guessing a conversion.
            logger.error("Kamino vault hydration failed: \(error.localizedDescription, privacy: .public)")
            self.error = error
            return
        }

        await resolveEligibility(info: info)
        setupForm()
        unitPrice = await preparer.resolveUnitPrice()

        installValidators(info: info)
    }

    // MARK: - Continue

    /// What the verify screen needs, built from ONE reading of the amount.
    ///
    /// The two travel together for the same reason they do on the deposit form:
    /// preparing takes several network round trips and the amount field stays
    /// editable throughout, so a summary built from a second read could describe
    /// a different withdraw from the one inside the bytes.
    struct WithdrawHandoff {
        let payload: KeysignPayload
        let transaction: SendTransaction
        /// The shares the transaction burns. Surfaced so a caller can assert on
        /// the unit that is actually in the bytes.
        let shares: KaminoShareAmount
    }

    /// Builds the payload the verify screen signs and the summary it shows, or
    /// `nil` with `error` set.
    func makeWithdraw() async -> WithdrawHandoff? {
        guard let vaultInfo, let withdrawCoin else { return nil }

        // Re-read at the moment of building, not from a flag set at load: the
        // form has been open, and a refusal must be the last word rather than
        // something that was true when the screen appeared.
        if let unavailableReason {
            error = unavailableReason
            return nil
        }
        guard let held, let maximumTokens else {
            error = KaminoWithdrawError.positionUnreadable
            return nil
        }

        // One capture of the amount, and one conversion of it. Everything below
        // — the request, the payload, the summary — is derived from these two
        // values and never re-reads the field.
        guard let amount = enteredAmount(), amount.baseUnits > 0 else {
            error = KaminoServiceError.invalidAmount(amountField.value)
            return nil
        }

        // The form's own gate, enforced here rather than trusted from there.
        // `FormScreen` disables Continue only on its explicit flag and never on
        // `validForm`, so an amount the balance validator rejected still arrives
        // — and an amount above the position must be a refusal, never a full
        // withdraw, or one mistyped digit would exit the whole position.
        guard amount.baseUnits <= maximumTokens.baseUnits else {
            error = AmountBalanceValidator.ValidationError.exceedsBalance
            return nil
        }

        guard let shares = KaminoWithdrawMath.shares(
            forTokens: amount,
            held: held.maximum,
            maximumTokens: maximumTokens,
            tokensPerShare: vaultInfo.tokensPerShare,
            shareDecimals: descriptor.sharesDecimals
        ), shares.isValidRequestAmount else {
            error = KaminoServiceError.invalidAmount(amountField.value)
            return nil
        }
        guard shares.baseUnits >= vaultInfo.minWithdraw.baseUnits else {
            guard let minimum = minimumWithdraw else {
                error = KaminoServiceError.conversionFailed
                return nil
            }
            error = KaminoWithdrawError.belowMinimum(minimum: minimum.apiString, ticker: ticker)
            return nil
        }

        // What the shares are worth, rather than what was typed. The transaction
        // burns shares; this is their projection at the current rate, and on a
        // full withdraw it is the whole position rather than the display-
        // truncated figure the 100% button wrote into the field.
        guard let tokenValue = shares.tokenValue(
            tokensPerShare: vaultInfo.tokensPerShare,
            tokenDecimals: descriptor.tokenDecimals
        ) else {
            error = KaminoServiceError.conversionFailed
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // The split travels with the amount. Which transaction the API
            // builds depends on it — a request inside the unstaked balance gets
            // two instructions, one above it gets five — and the validator has
            // to require the one that was actually asked for rather than accept
            // whichever came back.
            let prepared = try await preparer.prepareWithdraw(
                vault: vaultInfo,
                owner: withdrawCoin.address,
                request: KaminoWithdrawRequest(shares: shares, unstakedShares: held.unstaked),
                unitPrice: unitPrice
            )
            let payload = try KaminoKeysignPayloadFactory.makeWithdraw(
                prepared: prepared,
                vaultInfo: vaultInfo,
                shares: shares,
                tokenValue: tokenValue,
                coin: withdrawCoin,
                vault: vault
            )
            return WithdrawHandoff(
                payload: payload,
                transaction: displayTransaction(tokenValue: tokenValue, coin: withdrawCoin),
                shares: shares
            )
        } catch {
            logger.error("Kamino withdraw build failed: \(error.localizedDescription, privacy: .public)")
            self.error = describe(buildFailure: error, requested: amount)
            return nil
        }
    }

    /// Display-only transaction for the verify summary. The signed bytes come
    /// from the pre-built payload, so this exists purely to name the asset, the
    /// amount and where it lands.
    ///
    /// Rendered in the device's own locale rather than as the POSIX `apiString`:
    /// everything downstream reads `SendTransaction.amount` back through
    /// `parseInput`, which tries the device locale first, so a POSIX `10.123456`
    /// on a comma-decimal device would read as ten million.
    func displayTransaction(tokenValue: KaminoTokenAmount, coin: Coin) -> SendTransaction {
        SendTransaction.empty(coin: coin, vault: vault).with(
            toAddress: coin.address,
            amount: tokenValue.decimalValue.formatToDecimal(digits: descriptor.tokenDecimals)
        )
    }

    // MARK: - Amount

    /// The entered amount in the vault's TOKEN base units, parsed exactly. The
    /// form is asset-denominated; the conversion to shares happens once, at
    /// build time, through `KaminoWithdrawMath`.
    func enteredAmount() -> KaminoTokenAmount? {
        KaminoAmountInput.tokenAmount(amountField.value, decimals: descriptor.tokenDecimals)
    }

    // MARK: - Private

    /// Reads the user's position and decides what may be withdrawn from it.
    ///
    /// A failed read leaves nothing available. Falling back to the persisted
    /// snapshot would be worse than useless here: that figure is a token value
    /// derived from a rate, and sizing a withdraw from it is exactly the
    /// round-trip this flow refuses to perform.
    private func resolveEligibility(info: KaminoVaultInfo) async {
        guard let owner = withdrawCoin?.address else {
            eligibility = .empty
            return
        }

        do {
            let positions = try await service.fetchPositions(owner: owner)
            eligibility = KaminoWithdrawEligibility.resolve(
                response: positions.first { $0.vaultAddress == descriptor.address },
                shareDecimals: descriptor.sharesDecimals
            )
        } catch {
            logger.error("Kamino position read failed: \(error.localizedDescription, privacy: .public)")
            eligibility = .unreadable
            self.error = error
            return
        }

        guard let withdrawable = eligibility?.withdrawableShares else { return }
        guard let maximum = KaminoWithdrawMath.maximumTokens(
            shares: withdrawable.maximum,
            tokensPerShare: info.tokensPerShare,
            tokenDecimals: descriptor.tokenDecimals
        ) else {
            eligibility = .unreadable
            return
        }

        held = withdrawable
        maximumTokens = maximum
        availableAmount = maximum.decimalValue
    }

    /// Installed unconditionally. With no position, or one that cannot be
    /// withdrawn, the available amount is zero and the balance validator makes
    /// the form uncompletable — which is the honest outcome, rather than a
    /// Continue button that silently does nothing.
    private func installValidators(info: KaminoVaultInfo) {
        if let held, let maximumTokens {
            amountField.validators.append(
                KaminoMinWithdrawValidator(
                    held: held.maximum,
                    maximumTokens: maximumTokens,
                    minimumShares: info.minWithdraw,
                    tokensPerShare: info.tokensPerShare,
                    tokenDecimals: descriptor.tokenDecimals,
                    shareDecimals: descriptor.sharesDecimals,
                    errorMessage: minimumWithdrawText
                )
            )
        }
        amountField.validators.append(AmountBalanceValidator(balance: availableAmount))
    }

    /// Turns a build failure into something the user can act on.
    ///
    /// A withdraw the vault cannot settle out of its liquid balance is the one
    /// failure with a legible cause, and this names it — by comparing the
    /// request against the vault's published buffer, NOT by decoding a program
    /// error. No delayed-liquidity failure has ever been observed, so there is
    /// no error code to match on and this does not pretend there is: it reports
    /// a shortfall it can see, and leaves every other failure to say what it
    /// said.
    private func describe(buildFailure: Error, requested: KaminoTokenAmount) -> Error {
        guard let preparation = buildFailure as? KaminoPreparationError,
              case .simulationFailed = preparation,
              let available = KaminoWithdrawLiquidity.resolve(
                  requested: requested,
                  available: vaultInfo?.tokensAvailable
              ).availableTokens
        else { return buildFailure }

        return KaminoWithdrawError.insufficientLiquidity(available: available.apiString, ticker: ticker)
    }

    /// The wallet coin a withdraw from `descriptor` settles into.
    ///
    /// The wrapped-SOL vault pays out wSOL and closes the account, unwrapping it
    /// back to native SOL, so that vault resolves to the native coin. Everything
    /// else matches on the pinned mint, never on ticker.
    private static func resolveWithdrawCoin(descriptor: KaminoVaultDescriptor, vault: Vault) -> Coin? {
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

/// Why a withdraw cannot be made, in the user's terms.
enum KaminoWithdrawError: Error, LocalizedError, Equatable {
    case nothingToWithdraw
    case positionUnreadable
    case belowMinimum(minimum: String, ticker: String)
    case insufficientLiquidity(available: String, ticker: String)

    var errorDescription: String? {
        switch self {
        case .nothingToWithdraw:
            return "kaminoWithdrawNothing".localized
        case .positionUnreadable:
            return "kaminoWithdrawPositionUnreadable".localized
        case .belowMinimum(let minimum, let ticker):
            return String(format: "kaminoWithdrawMinimum".localized, minimum, ticker)
        case .insufficientLiquidity(let available, let ticker):
            return String(format: "kaminoWithdrawInsufficientLiquidity".localized, available, ticker)
        }
    }
}
