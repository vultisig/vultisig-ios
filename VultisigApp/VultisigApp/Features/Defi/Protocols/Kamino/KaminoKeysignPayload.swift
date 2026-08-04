//
//  KaminoKeysignPayload.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Marks a `KeysignPayload` whose `signSolana` bytes are a Kamino vault
/// transaction **this app built, validated and simulated**.
///
/// It exists for one reason: the pre-keysign blockhash refresh has to know
/// whether it may edit those bytes. Splicing a fresh blockhash into a raw Solana
/// transaction is only safe when the 32 bytes in that slot really are a
/// blockhash — a durable-nonce transaction keeps its nonce value there, and any
/// other party's bytes are theirs to define. This app's own Kamino transactions
/// are neither, and their blockhash genuinely does need refreshing, because it
/// was set by the Kamino API when the form was still open.
///
/// Local-only, like `solanaStakingPayload`: it is not round-tripped through the
/// proto `KeysignPayload`. The refresh runs on the initiating device, before the
/// bytes are relayed, so a co-signer receives the already-refreshed transaction
/// and needs no marker to sign it.
struct KaminoKeysignPayload: Codable, Hashable {

    enum Operation: String, Codable {
        case deposit
        case withdraw
    }

    /// The curated vault this transaction targets.
    let vaultAddress: String
    let operation: Operation
    /// The amount as it appears in the instruction, in the operation's own unit:
    /// underlying-token base units for a deposit, SHARE base units for a
    /// withdraw. The API takes the same `amount` field for both actions with
    /// inverted units, so the unit travels with the operation rather than being
    /// inferred at the far end.
    let amountBaseUnits: String
    let amountDecimals: Int

    init(vaultAddress: String, operation: Operation, amount: some KaminoBaseUnitAmount) {
        self.vaultAddress = vaultAddress
        self.operation = operation
        self.amountBaseUnits = String(amount.baseUnits)
        self.amountDecimals = amount.decimals
    }

    /// The registry entry for this transaction's vault, or `nil` when the app no
    /// longer curates it. Read rather than stored, so the marker can never carry
    /// a vault identity of its own.
    var descriptor: KaminoVaultDescriptor? {
        KaminoVaultRegistry.descriptor(for: vaultAddress)
    }
}
