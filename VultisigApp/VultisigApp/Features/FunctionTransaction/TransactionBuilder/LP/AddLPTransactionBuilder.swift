//
//  AddLPTransactionBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/11/2025.
//

import Foundation
import VultisigCommonData

struct AddLPTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let amount: String
    let poolName: String
    let pairedAddress: String?
    let sendMaxAmount: Bool

    /// Where the deposit is sent, resolved for **this** asset at the moment the
    /// transaction was made — the L1 inbound vault for a native deposit, the
    /// router contract for an ERC-20 one, and the empty string for a
    /// protocol-native deposit, which rides a `MsgDeposit` and names no
    /// recipient.
    ///
    /// It is stored rather than computed, and that is the fix. This property
    /// used to return `.empty` under a comment claiming it returned the inbound
    /// address, so every L1 deposit built here named no recipient; and the form
    /// it replaced resolved one address on load and then let its pool picker
    /// reassign the asset underneath it, so an ERC-20 deposit could approve the
    /// inbound vault as its spender and a native one could be signed straight
    /// at the router contract.
    ///
    /// The ERC-20 approval is **not** built here on purpose. The signing
    /// boundary derives it from the transaction's own recipient
    /// (`ThorchainRouterDepositBuilder.synthesizeRouterDeposit`), so the
    /// approved spender and the deposit target are the same address by
    /// construction. A second, independently-built spender is exactly how the
    /// two came apart before.
    let toAddress: String

    var memo: String {
        let address = pairedAddress?.nilIfEmpty
        let lpData = AddLPMemoData(pool: poolName, pairedAddress: address)
        return lpData.memo
    }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        // `pool` is what marks this transaction an LP add at the signing
        // boundary, which is where an ERC-20 deposit picks up its router shim.
        dict.set("pool", poolName)
        if let pairedAddress {
            dict.set("pairedAddress", pairedAddress)
        }
        dict.set("memo", memo)
        return dict
    }

    var transactionType: VSTransactionType {
        .unspecified
    }

    var wasmContractPayload: WasmExecuteContractPayload? {
        nil
    }
}
