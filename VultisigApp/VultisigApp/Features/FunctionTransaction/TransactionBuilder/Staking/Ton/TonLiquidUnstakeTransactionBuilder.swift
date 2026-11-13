//
//  TonLiquidUnstakeTransactionBuilder.swift
//  VultisigApp
//

import BigInt
import Foundation
import OSLog
import VultisigCommonData
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-liquid-unstake-builder")

/// Tonstakers unstake: a TEP-74 burn of tsTON sent to the user's own tsTON jetton wallet, with
/// the pool's withdrawal-flags cell and `Tonstakers.unstakeAttachedValue` attached for the hops.
struct TonLiquidUnstakeTransactionBuilder: TransactionBuilder {
    /// Native TON: it pays the attached value and the network fee.
    let coin: Coin
    let sendMaxAmount: Bool = false
    let memo: String = ""
    /// The user's tsTON jetton wallet in bounceable form (burn destination).
    let toAddress: String
    /// Always present: the builder only exists once the burn body is built.
    let tonStakePayload: TonStakePayload?

    /// `nil` when the amount is not positive, the owner address is not TON, or the body fails.
    init?(coin: Coin, jettonWalletAddress: String, tsTONAmount: BigInt) {
        guard tsTONAmount > 0 else {
            logger.error("Tonstakers burn amount non-positive")
            return nil
        }
        // Jetton wallets are active contracts; bounceable so a failed burn refunds.
        let wallet = TONAddressConverter.toUserFriendly(address: jettonWalletAddress, bounceable: true, testnet: false)
            ?? jettonWalletAddress
        do {
            guard let body = try Tonstakers.burnBody(amount: tsTONAmount, responseAddress: coin.address) else {
                logger.error("Tonstakers burn: owner address is not a TON address")
                return nil
            }
            self.coin = coin
            self.toAddress = wallet
            self.tonStakePayload = TonStakePayload(messages: [
                TonMessage(to: wallet, amount: Tonstakers.unstakeAttachedValue.description, payload: body)
            ])
        } catch {
            logger.error("Failed to build Tonstakers burn body: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// TON the transfer carries (the attached value); the tsTON rides in the body.
    var amount: String {
        let value = Decimal(string: Tonstakers.unstakeAttachedValue.description) ?? 0
        return (value / pow(Decimal(10), coin.decimals)).description
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
}
