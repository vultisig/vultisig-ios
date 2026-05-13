//
//  SendCryptoLogic.swift
//  VultisigApp
//
//  Pure helpers for the send flow. Every function takes only the primitives
//  it actually reads — no shared draft/store type. The form ViewModel
//  (mutable) and `SendTransaction` (immutable hand-off, lands in Phase B)
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
    /// validated in TronFreezeView / TronUnfreezeView.
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

    /// Polkadot + Ripple have an existential deposit: the chain reaps accounts
    /// whose remaining balance falls below it. Other chains never reap.
    static func canBeReaped(coin: Coin, amount: String, gas: BigInt) -> Bool {
        let tickers = [Chain.polkadot.ticker, Chain.ripple.ticker]
        guard tickers.contains(coin.ticker) else { return false }

        let totalBalance = BigInt(coin.rawBalance) ?? .zero
        let totalTransactionCost = amountInRaw(coin: coin, amount: amount) + gas
        let remainingBalance = totalBalance - totalTransactionCost

        switch coin.chainType {
        case .Polkadot:
            return remainingBalance < PolkadotHelper.defaultExistentialDeposit
        case .Ripple:
            return remainingBalance < RippleHelper.defaultExistentialDeposit
        default:
            return false
        }
    }

    /// A send is a "deposit" (memo-bearing function call) iff the memo
    /// dictionary carries entries AND the chain supports memos. UTXO, Ripple,
    /// and Solana sends never carry function-call memos in this flow.
    static func isDeposit(coin: Coin, memoFunctionDictionary: [String: String]) -> Bool {
        !memoFunctionDictionary.isEmpty
            && ![ChainType.UTXO, ChainType.Ripple, ChainType.Solana].contains(coin.chainType)
    }

    // MARK: - Display: fees

    /// Human-readable gas/fee row. EVM shows Gwei. UTXO + Cardano show the
    /// planned `fee` (a true amount). Everything else shows `gas` (per-unit).
    /// Caller resolves `gasNativeCoin` — for native sends it's the same coin;
    /// for ERC20s it's the EVM-native sibling looked up against the vault.
    static func gasInReadable(coin: Coin, gasNativeCoin: Coin, gas: BigInt, fee: BigInt) -> String {
        if coin.chain.chainType == .EVM {
            guard let weiPerGWeiDecimal = Decimal(string: EVMHelper.weiPerGWei.description) else {
                return .empty
            }
            return "\(gasDecimal(gas: gas) / weiPerGWeiDecimal) \(coin.chain.feeUnit)"
        }

        let decimals = gasNativeCoin.decimals
        let feeToDisplay = (coin.chainType == .UTXO || coin.chainType == .Cardano) ? fee : gas
        let feeDecimal = Decimal(feeToDisplay)

        return "\((feeDecimal / pow(10, decimals)).formatToDecimal(digits: decimals).description) \(gasNativeCoin.ticker)"
    }
}
