//
//  SendCryptoLogic.swift
//  VultisigApp
//
//  Pure helpers for the send flow. Every function takes only the primitives
//  it actually reads — no shared draft/store type. The form ViewModel
//  (mutable) and `FunctionCallForm` (immutable hand-off, lands in Phase B)
//  feed their own fields in via convenience computed properties.
//
//  Mirrors the shape of `SwapCryptoLogic`.
//

import BigInt
import Foundation

enum SendCryptoLogic {
    // MARK: - Amount conversions

    static func amountDecimal(coin: Coin, amount: String) -> Decimal {
        amount.toDecimal().truncated(toPlaces: coin.decimals)
    }

    static func amountInRaw(coin: Coin, amount: String) -> BigInt {
        let decimals = coin.decimals
        let amountInDecimals = amountDecimal(coin: coin, amount: amount) * pow(10, decimals)
        return amountInDecimals.description.toBigInt(decimals: decimals)
    }

    static func gasDecimal(gas: BigInt) -> Decimal {
        Decimal(gas)
    }

    // MARK: - Branching predicates

    /// Returns true if the requested amount + applicable fee exceeds the coin's
    /// raw balance. TRON staking operations short-circuit — balance is already
    /// validated in TronFreezeScreen / TronUnfreezeScreen.
    static func isAmountExceeded(
        coin: Coin,
        amount: String,
        sendMaxAmount: Bool,
        fee: BigInt,
        gas: BigInt,
        isStakingOperation: Bool
    ) -> Bool {
        let isTronStaking = coin.chain == .tron && isStakingOperation
        if isTronStaking {
            return false
        }

        let amountRaw = amountInRaw(coin: coin, amount: amount)
        let balanceRaw = coin.rawBalance.toBigInt(decimals: coin.decimals)

        if (sendMaxAmount && (coin.chainType == .UTXO || coin.chainType == .Cardano || coin.chainType == .Ton))
            || !coin.isNativeToken {
            return amountRaw > balanceRaw
        }

        // UTXO and Cardano use the planned `fee` (sats / lovelaces);
        // every other chain uses `gas` (per-unit cost).
        let feeToUse = (coin.chainType == .UTXO || coin.chainType == .Cardano) ? fee : gas
        return amountRaw + feeToUse > balanceRaw
    }

    /// Existential deposit for the coin's chain, or `.zero` for chains that
    /// don't reap. Scoped by `chain`, NOT `chainType`: Bittensor (TAO) shares
    /// `chainType == .Polkadot` with DOT but signs `transfer_allow_death`, so it
    /// permits full-balance sends and has no enforced ED here.
    static func existentialDeposit(for coin: Coin) -> BigInt {
        switch coin.chain {
        case .polkadot:
            return PolkadotHelper.defaultExistentialDeposit
        case .ripple:
            return RippleHelper.defaultExistentialDeposit
        default:
            return .zero
        }
    }

    /// Polkadot + Ripple have an existential deposit: the chain reaps accounts
    /// whose remaining balance falls below it (and the app signs
    /// `transfer_keep_alive` on DOT, which the chain rejects outright when it
    /// would reap the sender). Other chains never reap. Returns true when the
    /// requested send would leave the *sender* below the existential deposit.
    static func canBeReaped(coin: Coin, amount: String, gas: BigInt) -> Bool {
        let existentialDeposit = existentialDeposit(for: coin)
        guard existentialDeposit > .zero else { return false }

        let totalBalance = BigInt(coin.rawBalance) ?? .zero
        let totalTransactionCost = amountInRaw(coin: coin, amount: amount) + gas
        let remainingBalance = totalBalance - totalTransactionCost

        return remainingBalance > .zero && remainingBalance < existentialDeposit
    }

    /// Some chains enforce a protocol minimum value on every output (e.g.
    /// Cardano's ~1.4 ADA UTXO floor). A native send below the chain's floor is
    /// accepted by the wallet but silently dropped by the node, so block it
    /// here — before the keysign ceremony — to match Android. Token sends carry
    /// their own floor on the bundled output and are exempt. `amount` is the
    /// recipient output in both cases — for MAX sends `computeMaxAmount` already
    /// nets out the fee — so this also blocks a MAX send when the whole vault
    /// holds less than the floor.
    static func isBelowMinimumSendAmount(coin: Coin, amount: String) -> Bool {
        guard coin.isNativeToken, let minimum = coin.chain.minimumSendAmount else {
            return false
        }
        return amountInRaw(coin: coin, amount: amount) < minimum
    }

    /// A send is a "deposit" (memo-bearing function call) iff the memo
    /// dictionary carries entries AND the chain supports memos. UTXO, Ripple,
    /// and Solana sends never carry function-call memos in this flow.
    static func isDeposit(coin: Coin, memoFunctionDictionary: [String: String]) -> Bool {
        !memoFunctionDictionary.isEmpty
            && ![ChainType.UTXO, ChainType.Ripple, ChainType.Solana].contains(coin.chainType)
    }

    // MARK: - Fiat ↔ coin conversion (pure math)

    /// Convert a fiat-typed value into the equivalent coin amount string.
    /// Returns nil if either the input parses to ≤0 or the coin has no
    /// price (in which case the caller clears the field). The string is
    /// pre-truncated to the coin's decimals so SwiftUI bindings round-trip
    /// cleanly.
    static func fiatToCoinAmount(fiat: String, coin: Coin) -> String? {
        let fiatDecimal = fiat.toDecimal()
        guard fiatDecimal > 0, coin.price > 0 else { return nil }
        let coinDecimal = fiatDecimal / Decimal(coin.price)
        return formatAmountInput(coinDecimal.truncated(toPlaces: coin.decimals), digits: coin.decimals)
    }

    /// Convert a coin-typed value into its fiat equivalent string (2-decimal
    /// rounded but expressed using the coin's decimals format so binding
    /// values stay consistent). Returns nil for empty / zero / negative
    /// inputs.
    static func coinAmountToFiat(amount: String, coin: Coin) -> String? {
        let coinDecimal = amount.toDecimal()
        guard coinDecimal > 0 else { return nil }
        let fiatDecimal = coinDecimal * Decimal(coin.price)
        return formatAmountInput(fiatDecimal.truncated(toPlaces: 2), digits: coin.decimals)
    }

    // MARK: - Max amount

    /// Compute the max sendable amount given a resolved fee. Caller fetches the
    /// per-chain fee (UTXO byte-fee × planned bytes, EVM gasPrice × gasLimit,
    /// chain-specific gas, etc.) and feeds the BigInt in here. Pure math; the
    /// async fetches live in the interactor.
    static func computeMaxAmount(coin: Coin, fee: BigInt) -> String {
        let maxValue: Decimal
        if coin.chain == .terraClassic {
            // Terra Classic charges a proportional burn tax on the send amount,
            // so the simple `balance − fee` overshoots: the tax on that max
            // amount is unfunded. Solve the fixed point
            //   max = (balance − baseGasFee) / (1 + rate)
            // using the conservative fallback rate (the Verify screen re-fetches
            // the live rate and revalidates before signing).
            maxValue = terraClassicMaxValue(coin: coin, baseGasFee: fee)
        } else {
            // Reserve the existential deposit on chains that reap the sender (DOT
            // signs `transfer_keep_alive`, which fails outright if the send would
            // drop the sender below ED). Reserved on top of the fee so max-send
            // settles at `balance − fee − ED`. Zero for every other chain,
            // including Bittensor/TAO (`transfer_allow_death`).
            maxValue = coin.getMaxValue(fee + existentialDeposit(for: coin))
        }
        let digits = coin.decimals > 8 ? 8 : coin.decimals
        return formatAmountInput(maxValue, digits: digits)
    }

    /// Fixed-point max amount for Terra Classic accounting for the proportional
    /// burn tax. `baseGasFee` is the flat gas portion in the send denom.
    private static func terraClassicMaxValue(coin: Coin, baseGasFee: BigInt) -> Decimal {
        let rawBalance = coin.rawBalance.toBigInt()
        let spendableRaw = rawBalance - baseGasFee
        guard spendableRaw > 0 else { return 0 }

        let spendable = Decimal(string: spendableRaw.description) ?? 0
        let divisor = 1 + TerraClassicTax.fallbackBurnTaxRate
        let maxRaw = spendable / divisor

        let scaled = maxRaw / pow(10, coin.decimals)
        return scaled < .zero ? 0 : scaled.truncated(toPlaces: coin.decimals - 1)
    }

    /// Apply a percentage (0–100) to a max amount string. Used by the
    /// "25% / 50% / 75%" preset buttons in the Details screen.
    static func applyPercentage(maxAmount: String, percentage: Double, coinDecimals: Int) -> String {
        let multiplier = Decimal(percentage) / 100
        let target = maxAmount.toDecimal() * multiplier
        let digits = coinDecimals > 8 ? 8 : coinDecimals
        return formatAmountInput(target, digits: digits)
    }

    private static func formatAmountInput(_ value: Decimal, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = Locale.current.decimalSeparator ?? "."
        formatter.usesGroupingSeparator = false
        formatter.roundingMode = .down
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    // MARK: - Display: fees

    /// Human-readable gas/fee row. EVM, UTXO and Cardano show the total `fee`
    /// (a true amount) in the native coin, matching the joining device's
    /// `JoinKeysignGasViewModel`. Everything else shows `gas` (per-unit).
    /// Caller resolves `gasNativeCoin` — for native sends it's the same coin;
    /// for ERC20s it's the EVM-native sibling looked up against the vault.
    static func gasInReadable(coin: Coin, gasNativeCoin: Coin, gas: BigInt, fee: BigInt) -> String {
        let decimals = gasNativeCoin.decimals
        let usesTotalFee = coin.chainType == .EVM || coin.chainType == .UTXO || coin.chainType == .Cardano
        let feeToDisplay = usesTotalFee ? fee : gas
        let feeDecimal = Decimal(feeToDisplay)

        return "\((feeDecimal / pow(10, decimals)).formatToDecimal(digits: decimals).description) \(gasNativeCoin.ticker)"
    }
}
