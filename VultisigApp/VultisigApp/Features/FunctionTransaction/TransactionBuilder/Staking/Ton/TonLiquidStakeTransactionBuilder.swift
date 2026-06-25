//
//  TonLiquidStakeTransactionBuilder.swift
//  VultisigApp
//

import Foundation
import OSLog
import VultisigCommonData
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-liquid-stake-builder")

/// Builds a Tonstakers liquid-staking deposit: send `amount` TON to the
/// Tonstakers pool with the `tonstakers_pool_deposit` (0x47d54391) body as the
/// message payload (NOT a text comment). The pool mints tsTON back to the user.
///
/// Routed through the TonConnect `customPayload` signing path via
/// `tonStakePayload`, so the verify/keysign bridge attaches `.signTon` and both
/// MPC devices sign the identical deposit body.
struct TonLiquidStakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// Stake amount in human-decimal TON.
    let amount: String
    let sendMaxAmount: Bool = false

    let memo: String = ""

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    var toAddress: String { TonstakersConstants.poolAddress }

    var tonStakePayload: TonStakePayload? {
        // amountInRaw: stake amount scaled to nanotons. The TonMessage amount
        // must match the SendTransaction amount the verify screen previews.
        let nano = amount.toBigInt(decimals: coin.decimals)
        guard nano > 0 else {
            logger.error("Tonstakers deposit amount non-positive")
            return nil
        }
        let payload: String
        do {
            payload = try TonstakersBodyBuilder.depositBody()
        } catch {
            logger.error("Failed to build Tonstakers deposit body: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let message = TonMessage(
            to: TonstakersConstants.poolAddress,
            amount: nano.description,
            payload: payload
        )
        return TonStakePayload(messages: [message])
    }
}
