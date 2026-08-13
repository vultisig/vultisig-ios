//
//  UnstakeTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine
import OSLog

private let logger = Log.send.viewModel

/// Reads a position's auto-compound receipt balance, in the position's base
/// units, or `nil` for a ticker that has no receipt to read.
///
/// Injected so the ordering of that read against user input is controllable —
/// the whole point of the unstake sheet's balance load is that it can land
/// after the user has typed. Strings in, `Decimal` out keeps `Coin` (a SwiftData
/// `@Model`) off the boundary.
typealias AutocompoundBalanceReader = (_ ticker: String, _ address: String) async throws -> Decimal?

/// The production read behind the auto-compound ceiling: THORChain's per-position
/// receipt endpoints.
enum THORChainAutocompoundBalance {
    static func read(ticker: String, address: String) async throws -> Decimal? {
        switch ticker.uppercased() {
        case "TCY":
            return try await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: address)
        case "BRUNE":
            return try await ThorchainService.shared.fetchBRuneAutoCompoundAmount(address: address)
        case "RUJI":
            // The sRUJI receipt share balance — what `liquid.unbond` spends. Not a
            // display value: shares are worth more than 1 RUJI each and drift
            // further apart as the pool compounds.
            return try await ThorchainService.shared.fetchRujiStakingReceiptAmount(address: address)
        default:
            return nil
        }
    }
}

/// The main actor is already inferred here — `Form` is `@MainActor` and the
/// conformance is stated on the declaration — but it is spelled out because the
/// invariant is load-bearing and arrives from another file: every stored property
/// is either a `@Published` the sheet renders from or the `Coin` SwiftData
/// `@Model` the builders read. Moving that conformance into an extension would
/// silently drop the isolation and leave a `@Model` on whatever thread the
/// balance read resumed on. Costs the network read nothing: the reader is a
/// non-isolated async function, so it runs off the main actor either way.
@MainActor
final class UnstakeTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let isAutocompound: Bool
    let availableToUnstake: Decimal?

    @Published var percentageSelected: Double? = 100
    @Published var availableAmount: Decimal = 0
    /// Published because `isContinueDisabled` is derived from it, and a read that
    /// *failed* moves nothing else — without this the button would keep rendering
    /// against the state the last redraw happened to see.
    @Published var autocompoundBalance: Decimal = 0
    @Published var validForm: Bool = false
    @Published var amountField = FormField(label: "amount".localized)

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        amountField
    ]

    /// The in-flight receipt-balance read, so a caller can await the revision
    /// instead of racing it.
    private(set) var autocompoundLoadTask: Task<Void, Never>?
    /// Whether the receipt read completed. A failed read reports zero exactly as
    /// an empty position does, and only one of the two may lower the ceiling.
    private var autocompoundBalanceDidLoad = false
    private let readAutocompoundBalance: AutocompoundBalanceReader

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(
        coin: Coin,
        vault: Vault,
        isAutocompound: Bool,
        availableToUnstake: Decimal? = nil,
        readAutocompoundBalance: @escaping AutocompoundBalanceReader = THORChainAutocompoundBalance.read
    ) {
        self.coin = coin
        self.vault = vault
        self.isAutocompound = isAutocompound
        self.availableToUnstake = availableToUnstake
        self.readAutocompoundBalance = readAutocompoundBalance
    }

    func onLoad() {
        setupForm()
        availableAmount = availableToUnstake ?? coin.stakedBalanceDecimal
        setupAmountField()

        // Started for exactly the positions the receipt balance funds — the same
        // predicate that disables Continue and blocks the builder — so a sheet can
        // never be left waiting on a balance it never asked for. bRUNE is what
        // separates that from `isAutocompound`: it spends receipt units whichever
        // card opened the sheet, so keying the read on the compound flag alone
        // would leave a bonded one permanently unable to build.
        guard isFundedFromReceiptBalance else { return }
        autocompoundLoadTask = Task { @MainActor [weak self] in
            await self?.fetchAutocompoundBalance()
            self?.applyLoadedAutocompoundBalance()
        }
    }

    /// Folds a ceiling that arrived from the network into a field the user may
    /// already have typed into.
    ///
    /// Deliberately *not* `setupAmountField()`: that resets `percentageSelected`
    /// to 100, and the amount is derived from the percentage, so re-running it
    /// would replace a typed value — or a percentage the user dragged — with the
    /// whole position, purely on network timing. Moving only the ceiling lets
    /// `AmountTextField` resolve both cases the way it already does on any
    /// `availableAmount` change: a selected percentage re-derives the amount from
    /// the corrected ceiling, and a typed amount is left alone while
    /// ``percentageFromAmount`` re-derives its fraction against that ceiling.
    private func applyLoadedAutocompoundBalance() {
        // A read that failed reports zero. Adopting it would drop the ceiling to
        // zero, reject whatever is in the field and dead-end the sheet on a
        // figure that was never real — strictly worse than the card figure it
        // replaced. A read that completed is allowed to lower the ceiling,
        // because then the position really is that small.
        guard receiptBalanceIsAvailableAmount, autocompoundBalanceDidLoad else { return }
        availableAmount = autocompoundBalance
        amountField.validators = amountValidators()

        // The form pipeline only re-validates when a field's *value* changes.
        // With a percentage selected the view is about to rewrite the field from
        // the new ceiling and the pipeline will pick that up; when the user
        // typed, the value stays put, so the revised validator has to drive its
        // own validation or `validForm` keeps answering against the replaced
        // ceiling — and a lowered ceiling would let an over-balance amount
        // through.
        guard percentageSelected == nil else { return }
        revalidateAmount()
    }

    private func revalidateAmount() {
        do {
            try amountField.validateErrors()
            validForm = true
        } catch {
            validForm = false
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
        // Every auto-compound redemption is funded from the receipt balance, and
        // a zero there means the read is still in flight, failed, or the position
        // is empty. All three build a wasm execute carrying no funds, which the
        // user can sign and pay a fee for while nothing moves.
        guard !isFundedFromReceiptBalance || autocompoundBalance > 0 else { return nil }

        switch coin.ticker.uppercased() {
        case "TCY":
            // Converts the amount straight to basis points instead of through a
            // whole percentage — see `WithdrawBasisPoints`. A zero means the
            // amount is too small for the memo to express;
            // `WithdrawMinimumAmountValidator` normally stops it reaching here,
            // and refusing to build is the backstop.
            let basisPoints = withdrawBasisPoints
            guard basisPoints >= WithdrawBasisPoints.min else { return nil }
            return TCYUnstakeTransactionBuilder(
                coin: coin,
                basisPoints: basisPoints,
                autoCompoundAmount: autocompoundBalance,
                sendMaxAmount: isMaxAmount,
                isAutoCompound: isAutocompound,
                stakedAmount: availableAmount
            )
        case "BRUNE":
            return BRUNEUnstakeTransactionBuilder(
                coin: coin,
                percentage: Int(resolvedPercentage),
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
                return RUJILiquidUnbondTransactionBuilder(
                    coin: coin,
                    percentage: Int(resolvedPercentage),
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
            // `POOL-:<bps>` is the same 0…10000 fractional withdrawal TCY's memo
            // is, on MAYAChain rather than THORChain, and it was reached the same
            // wrong way: `Int(percentage) * 100` spends 100 of the memo's 10 000
            // steps, so a step is a whole 1% of the position and everything
            // between two steps is floored away.
            let basisPoints = withdrawBasisPoints
            guard basisPoints >= WithdrawBasisPoints.min else { return nil }
            return CacaoUnstakeTransactionBuilder(coin: coin, bps: basisPoints)
        default:
            return nil
        }
    }

    /// Whether the message this position unstakes with is funded from the
    /// auto-compound receipt balance, and so cannot be built before that balance
    /// has been read. sRUJI's redemption is the clearest case — the share balance
    /// is not what bounds the amount field, so nothing else stops a zero — but
    /// sTCY and ybRUNE fund their `liquid.unbond` from it just the same.
    private var isFundedFromReceiptBalance: Bool {
        switch coin.ticker.uppercased() {
        case "TCY", "RUJI":
            return isAutocompound
        case "BRUNE":
            // bRUNE is only ever staked through the ybRUNE compound position, so
            // its unstake always spends receipt units.
            return true
        default:
            return false
        }
    }

    /// Whether no amount at all can be withdrawn yet, so Continue reads as
    /// disabled instead of silently refusing. An auto-compound redemption is
    /// funded from the receipt balance, so while that read is in flight — or
    /// after it failed — there is nothing to sign no matter what the field says.
    var isContinueDisabled: Bool {
        isFundedFromReceiptBalance && autocompoundBalance <= 0
    }

    /// The percentage of the position the transaction withdraws.
    ///
    /// The percentage control and the amount field are two views of one value and
    /// exactly one of them owns it at a time: `AmountTextField` clears
    /// `percentageSelected` the moment the field is edited by hand, so a selected
    /// percentage means the field was derived from it, and its absence means the
    /// user typed and the percentage is derived back from the field. Derived
    /// against whatever ceiling is in force *now*, which is what lets a balance
    /// that lands late correct the fraction rather than the amount.
    var resolvedPercentage: Double {
        percentageSelected ?? percentageFromAmount
    }

    var percentageFromAmount: Double {
        AmountPercentageBinding.percentage(ofAmount: amountField.value.toDecimal(), available: availableAmount) ?? 0
    }

    /// Whether this position is addressed in ten-thousandths of itself — the unit
    /// THORChain's `tcy-:<bps>` and MAYAChain's `POOL-:<bps>` carry, and the unit
    /// the TCY auto-compound redemption scales its receipt shares by.
    ///
    /// What it decides is the FIELD: these positions carry
    /// `WithdrawMinimumAmountValidator`, so an amount too small for the memo to
    /// express is refused instead of quietly becoming a fee paid to withdraw
    /// nothing.
    ///
    /// ⚠️ It does not dispatch the conversion — `transactionBuilder`'s switch does
    /// that, because each ticker also selects a different builder. So this list and
    /// the branches that call `withdrawBasisPoints` are two statements of the same
    /// fact and have to be changed together. A branch converted without being added
    /// here gets the finer conversion with no floor under it, which is the
    /// round-to-zero hazard the validator exists to close.
    ///
    /// bRUNE/ybRUNE and RUJI-compound are deliberately absent: they scale receipt
    /// base units by `percentage / 100` instead of addressing the position in
    /// ten-thousandths, which is a different mechanism and a different change.
    private var withdrawsInBasisPoints: Bool {
        ["TCY", "CACAO"].contains(coin.ticker.uppercased())
    }

    /// The share of the position the memo will ask for, in basis points.
    ///
    /// Derived from the amount rather than from `percentageSelected`, because the
    /// amount is the finer of the two: the slider moves in whole percent, so
    /// reading the percentage would re-impose the very truncation this replaces.
    /// The two agree whenever the slider is what set the amount.
    ///
    /// Closing the position pins the ceiling exactly instead of deriving it, so a
    /// full exit can never leave a rounding remainder staked.
    var withdrawBasisPoints: Int {
        guard availableAmount > 0 else { return 0 }
        // Pinned rather than derived: the amount field renders 4 decimals, so on
        // a small position MAX can round to 9999 and leave a sliver staked.
        //
        // Only while the percentage still owns the value. Typing clears
        // `percentageSelected` without ever reaching `onPercentage`, so the flag
        // raised when the form opened at 100% outlives the selection it
        // describes — and pinning on it alone would withdraw the whole position
        // for an amount the user typed to be smaller.
        guard !isMaxAmount || percentageSelected == nil else { return WithdrawBasisPoints.max }
        return WithdrawBasisPoints.value(
            forAmount: amountField.value.toDecimal(),
            available: availableAmount
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }

    /// The validators the amount field carries for the ceiling in force now.
    ///
    /// Built in one place because a ceiling that arrives late has to reinstall
    /// the same chain against the new balance: rebuilding only the balance rule
    /// there would drop the basis-point minimum and let an amount too small to
    /// express pass validation.
    private func amountValidators() -> [FormFieldValidator] {
        var validators: [FormFieldValidator] = [
            AmountBalanceValidator(balance: self.availableAmount)
        ]
        if withdrawsInBasisPoints {
            // These memos ask for a fraction of the position in ten-thousandths,
            // so an amount can be positive, inside the balance, and still round
            // away to "withdraw nothing".
            validators.append(
                WithdrawMinimumAmountValidator(available: self.availableAmount, ticker: coin.ticker)
            )
        }
        return validators
    }

    func setupAmountField() {
        self.amountField.validators = amountValidators()
        self.percentageSelected = 100
        self.isMaxAmount = true
    }

    func fetchAutocompoundBalance() async {
        // Both `Coin` reads are taken here, before the suspension: the reader is
        // strings-in/`Decimal`-out precisely so the network hop never carries a
        // `@Model` across it.
        let ticker = coin.ticker
        let address = coin.address
        do {
            guard let amount = try await readAutocompoundBalance(ticker, address) else { return }
            autocompoundBalance = coin.valueWithDecimals(value: amount)
            autocompoundBalanceDidLoad = true
        } catch {
            logger.error(
                "Failed to fetch \(ticker, privacy: .public) autocompound balance: \(error.localizedDescription, privacy: .private)"
            )
            // Written together with the balance, always, so the flag cannot end up
            // describing a value that a later failure has since zeroed.
            autocompoundBalance = .zero
            autocompoundBalanceDidLoad = false
        }
    }
}
