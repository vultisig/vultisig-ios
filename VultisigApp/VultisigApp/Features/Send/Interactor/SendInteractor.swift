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

extension SendInteractor {
    /// Convenience overload that reads the 10 primitives off an immutable
    /// `SendTransaction`. Lets Verify-stage callers (which already hold the
    /// struct) skip the field-by-field unpacking.
    func fetchChainSpecific(tx: SendTransaction) async throws -> BlockChainSpecific {
        try await fetchChainSpecific(
            coin: tx.coin,
            toAddress: tx.toAddress,
            amount: tx.amountInRaw,
            memo: tx.memo.isEmpty ? nil : tx.memo,
            sendMaxAmount: tx.sendMaxAmount,
            isDeposit: tx.isDeposit,
            transactionType: tx.transactionType,
            gasLimit: tx.gasLimit,
            feeMode: tx.feeMode,
            fromAddress: tx.fromAddress
        )
    }

    /// Unified gas + fee fetch used by the Send Details form (both refresh
    /// and max-amount paths). EVM goes through `calculateEVMFee` to honor the
    /// dynamic fee mode; UTXO + Cardano read `fee` off the chain-specific
    /// (the byte-fee × planned size); other chains use `gas` as a flat fee.
    ///
    /// Callers that need the "fee that's actually deducted from THIS coin's
    /// balance" (e.g. computing max-amount) post-process the result: gas is
    /// paid in the native sibling for ERC20 / SPL etc., so non-native sources
    /// see `.zero` for the deductible fee even though the real gas/fee here
    /// is non-zero. That distinction stays at the call site — this method
    /// always returns the true on-chain values.
    func fetchGasAndFee(
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
    ) async throws -> SendInteractorFeeResult {
        let chainSpecific = try await fetchChainSpecific(
            coin: coin,
            toAddress: toAddress,
            amount: amount,
            memo: memo,
            sendMaxAmount: sendMaxAmount,
            isDeposit: isDeposit,
            transactionType: transactionType,
            gasLimit: gasLimit,
            feeMode: feeMode,
            fromAddress: fromAddress
        )

        switch coin.chainType {
        case .EVM:
            return try await calculateEVMFee(coin: coin, fromAddress: fromAddress, feeMode: feeMode)
        case .UTXO, .Cardano:
            return SendInteractorFeeResult(fee: chainSpecific.fee, gas: chainSpecific.gas)
        default:
            return SendInteractorFeeResult(fee: chainSpecific.gas, gas: chainSpecific.gas)
        }
    }
}
