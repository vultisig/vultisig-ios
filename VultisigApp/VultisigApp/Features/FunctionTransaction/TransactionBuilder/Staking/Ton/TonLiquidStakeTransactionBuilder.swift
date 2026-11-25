//
//  TonLiquidStakeTransactionBuilder.swift
//  VultisigApp
//

import BigInt
import Foundation
import OSLog
import VultisigCommonData

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-liquid-stake-builder")

/// Tonstakers deposit: a TON transfer to the pool carrying the `pool::deposit` body, signed
/// through the TonConnect `customPayload` path so every co-signer signs the same body.
///
/// `amount` is what the transfer carries; the pool stakes `amount − Tonstakers.depositFee` and
/// refunds what the mint chain does not spend (Android parity).
struct TonLiquidStakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// Deposit value in human-decimal TON, including the pool's 1 TON fee.
    let amount: String
    let sendMaxAmount: Bool = false
    let memo: String = ""
    /// Always present: the builder only exists once the deposit body is built, so Verify can
    /// never fall back to a bodyless transfer to the pool.
    let tonStakePayload: TonStakePayload?

    /// `nil` when the value is under `minimumValue` (nanotons, the same minimum the form
    /// enforces) or the body cannot be built.
    init?(coin: Coin, amount: String, minimumValue: BigInt) {
        let value = amount.toBigInt(decimals: coin.decimals)
        guard value > 0, value >= minimumValue else {
            logger.error("Tonstakers deposit below the pool minimum")
            return nil
        }
        do {
            let message = TonMessage(
                to: Tonstakers.poolAddress,
                amount: value.description,
                payload: try Tonstakers.depositBody()
            )
            self.coin = coin
            self.amount = amount
            self.tonStakePayload = TonStakePayload(messages: [message])
        } catch {
            logger.error("Failed to build Tonstakers deposit body: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { Tonstakers.poolAddress }
}
