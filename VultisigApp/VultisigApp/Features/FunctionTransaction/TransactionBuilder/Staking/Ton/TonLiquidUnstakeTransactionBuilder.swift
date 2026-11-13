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
    /// The user's tsTON jetton wallet, resolved against the tsTON master (burn destination).
    let jettonWalletAddress: String
    /// tsTON to burn, in base units.
    let tsTONAmount: BigInt

    let sendMaxAmount: Bool = false
    let memo: String = ""

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
    var toAddress: String { bounceableJettonWallet }

    /// Jetton wallets are always active contracts; send bounceable so a failed burn refunds.
    private var bounceableJettonWallet: String {
        TONAddressConverter.toUserFriendly(address: jettonWalletAddress, bounceable: true, testnet: false)
            ?? jettonWalletAddress
    }

    var tonStakePayload: TonStakePayload? {
        guard tsTONAmount > 0 else {
            logger.error("Tonstakers burn amount non-positive")
            return nil
        }
        do {
            guard let body = try Tonstakers.burnBody(amount: tsTONAmount, responseAddress: coin.address) else {
                logger.error("Tonstakers burn: owner address is not a TON address")
                return nil
            }
            let message = TonMessage(
                to: bounceableJettonWallet,
                amount: Tonstakers.unstakeAttachedValue.description,
                payload: body
            )
            return TonStakePayload(messages: [message])
        } catch {
            logger.error("Failed to build Tonstakers burn body: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
