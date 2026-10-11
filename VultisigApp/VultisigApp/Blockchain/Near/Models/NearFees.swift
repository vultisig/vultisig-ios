//
//  NearFees.swift
//  VultisigApp
//

import BigInt
import Foundation

/// NEAR fee arithmetic, transcribed from nearcore protocol 86 (release tag
/// 2.13.4): `runtime/runtime/src/config.rs` `calculate_tx_cost`,
/// `core/parameters/src/cost.rs` (an implicit receiver reserves
/// `create_account` + `add_full_access_key` gas whether or not it already
/// exists), `runtime/runtime/src/verifier.rs` `check_storage_stake` (NEP-448
/// exempts `storage_usage <= 770`) and the outright rejection when the balance
/// cannot cover the charge.
///
/// `account_creation_charge` is absent on purpose: nearcore collects it at
/// execution time out of the receipt's gas refund, so it is neither upfront nor
/// part of the balance requirement.
enum NearFees {

    /// NEP-448 zero-balance accounts reach this storage usage; `verifier.rs:40`.
    static let zeroBalanceStorageLimit: BigInt = 770

    /// `ParameterCost` as exposed by `transaction_costs` in the runtime config.
    struct ParameterCost {
        /// `send_sir` / `send_not_sir`: charged to convert the transaction into a receipt.
        let sendSir: BigInt
        let sendNotSir: BigInt
        let execution: BigInt
    }

    struct FeeConfig {
        let actionReceiptCreation: ParameterCost
        let transfer: ParameterCost
        let createAccount: ParameterCost
        let addFullAccessKey: ParameterCost
        /// Floor price for the gas attached to the receipt (`min_gas_purchase_price`).
        let minGasPurchasePrice: BigInt
        let storageAmountPerByte: BigInt
    }

    struct GasReservation {
        let burntGas: BigInt
        let remainingGas: BigInt
        let burntPrice: BigInt
        let receiptPrice: BigInt
        /// YoctoNEAR the sender must hold on top of the transfer amount.
        let reserved: BigInt
    }

    /// `senderIsReceiver` is nearcore's `sender_is_receiver`: a self-send pays
    /// the cheaper `send_sir` variants.
    static func gasReservation(
        config: FeeConfig,
        gasPrice: BigInt,
        senderIsReceiver: Bool,
        receiverIsImplicit: Bool
    ) -> GasReservation {
        let creationSendGas = receiverIsImplicit
            ? sendGas(config.createAccount, senderIsReceiver) + sendGas(config.addFullAccessKey, senderIsReceiver)
            : 0
        let creationExecGas = receiverIsImplicit
            ? config.createAccount.execution + config.addFullAccessKey.execution
            : 0

        let burntGas = sendGas(config.actionReceiptCreation, senderIsReceiver)
            + sendGas(config.transfer, senderIsReceiver)
            + creationSendGas
        let remainingGas = config.actionReceiptCreation.execution + config.transfer.execution + creationExecGas

        // Conversion gas is burnt at the block price; the receipt's gas is
        // purchased at a price floored by `min_gas_purchase_price`, a factor of
        // ten apart on mainnet.
        let burntPrice = gasPrice
        let receiptPrice = gasPrice > config.minGasPurchasePrice ? gasPrice : config.minGasPurchasePrice

        return GasReservation(
            burntGas: burntGas,
            remainingGas: remainingGas,
            burntPrice: burntPrice,
            receiptPrice: receiptPrice,
            reserved: burntGas * burntPrice + remainingGas * receiptPrice
        )
    }

    /// Balance that must stay behind to back the account's own storage.
    /// `locked` (staking) only relaxes this requirement — it never becomes
    /// spendable.
    static func storageReserve(storageUsage: BigInt, locked: BigInt, storageAmountPerByte: BigInt) -> BigInt {
        guard storageUsage > zeroBalanceStorageLimit else {
            return 0
        }
        let required = storageAmountPerByte * storageUsage
        return required > locked ? required - locked : 0
    }

    static func maxSendable(amount: BigInt, gasReservation: BigInt, storageReserve: BigInt) -> BigInt {
        let spendable = amount - gasReservation - storageReserve
        return spendable > 0 ? spendable : 0
    }

    /// Everything a send of `requestedAmount` must leave in the account, per
    /// `verifier.rs:305-342`.
    static func requiredAmount(requestedAmount: BigInt, gasReservation: BigInt, storageReserve: BigInt) -> BigInt {
        requestedAmount + gasReservation + storageReserve
    }

    private static func sendGas(_ cost: ParameterCost, _ senderIsReceiver: Bool) -> BigInt {
        senderIsReceiver ? cost.sendSir : cost.sendNotSir
    }
}
