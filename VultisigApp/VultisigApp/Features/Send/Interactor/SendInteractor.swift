//
//  SendInteractor.swift
//  VultisigApp
//
//  Protocol layer between the Send feature's ViewModels and the underlying
//  services (chain-specific data, fast vault, balance, payload factory). Lets
//  the VM tests drive happy/error paths through mocks instead of network
//  singletons. Mirrors `SwapInteractor`.
//
//  Note (send-pilot decision 3): `fetchChainSpecific` and `calculateEVMFee`
//  take `feeMode` explicitly. The legacy `SendCryptoVerifyLogic.calculateEVMFee`
//  hardcoded `.default`, which dropped the user's pinned fee mode on Verify
//  refresh. This protocol forces every caller to thread the field through.
//

import BigInt
import Foundation
import VultisigCommonData

protocol SendInteractor {
    /// Fast Vault eligibility for a given vault — exists on the server AND
    /// wasn't a local-only backup.
    func loadFastVault(vault: Vault) async -> Bool

    /// Chain-specific fee / nonce / blockhash data needed to assemble the
    /// keysign payload. `feeMode` controls EVM priority and UTXO byte-fee
    /// tier — never hardcode `.default` at the call site.
    func fetchChainSpecific(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        sendMaxAmount: Bool,
        isDeposit: Bool,
        transactionType: VSTransactionType,
        gasLimit: BigInt?,
        feeMode: FeeMode,
        fromAddress: String
    ) async throws -> BlockChainSpecific

    /// Compute the user-visible EVM network fee (Eip1559 / legacy gas) in the
    /// chain's native units. Caller resolves `feeMode` — passing it explicitly
    /// is the fix for the bug where Verify refresh ignored `tx.feeMode`.
    func calculateEVMFee(
        coin: Coin,
        fromAddress: String,
        feeMode: FeeMode
    ) async throws -> SendInteractorFeeResult

    /// Build the final keysign payload to hand off to signing. UTXO + Cardano
    /// chains plan a draft transfer internally; other chains read directly
    /// off `chainSpecific`.
    func buildKeysignPayload(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        chainSpecific: BlockChainSpecific,
        wasmExecuteContractPayload: WasmExecuteContractPayload?,
        vault: Vault
    ) async throws -> KeysignPayload

    /// Refresh balance for a single coin.
    func updateBalance(for coin: Coin) async
}

struct SendInteractorFeeResult: Equatable {
    let fee: BigInt
    let gas: BigInt
}
