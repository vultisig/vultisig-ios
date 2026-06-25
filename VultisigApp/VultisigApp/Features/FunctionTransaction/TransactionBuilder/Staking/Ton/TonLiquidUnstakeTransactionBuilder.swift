//
//  TonLiquidUnstakeTransactionBuilder.swift
//  VultisigApp
//

import Foundation
import OSLog
import VultisigCommonData
import BigInt

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-liquid-unstake-builder")

/// Builds a Tonstakers liquid-staking unstake: BURN the user's tsTON via a
/// TEP-74 `jetton_burn` (0x595f07bc) body sent to the user's tsTON jetton
/// wallet. The pool returns TON instantly when it has liquidity, otherwise via
/// a ~18h withdrawal NFT.
///
/// The jetton-wallet address, the tsTON burn amount (base units), and the
/// owner's response address are resolved upstream (async) by the unstake view
/// model; this builder only assembles the body and the TonConnect message.
struct TonLiquidUnstakeTransactionBuilder: TransactionBuilder {
    let coin: Coin
    /// The user's own wallet address — `response_destination` for excess gas.
    let ownerAddress: String
    /// The user's tsTON jetton wallet address (the burn destination).
    let jettonWalletAddress: String
    /// tsTON amount to burn, in base units (decimal string).
    let tsTONAmountRaw: String

    /// Displayed amount: the TON the burn carries for forward gas (not the
    /// burned tsTON, which rides in the body). Human-decimal TON.
    let amount: String
    let sendMaxAmount: Bool = false

    let memo: String = ""

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// The transfer goes to the user's tsTON jetton wallet.
    var toAddress: String { jettonWalletAddress }

    var tonStakePayload: TonStakePayload? {
        let payload: String
        do {
            payload = try TonstakersBodyBuilder.burnBody(
                amount: tsTONAmountRaw,
                responseAddress: ownerAddress
            )
        } catch {
            logger.error("Failed to build Tonstakers burn body: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let message = TonMessage(
            to: jettonWalletAddress,
            amount: TonstakersConstants.burnGasNano.description,
            payload: payload
        )
        return TonStakePayload(messages: [message])
    }
}
