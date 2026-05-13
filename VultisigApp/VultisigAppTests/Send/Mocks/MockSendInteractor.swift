//
//  MockSendInteractor.swift
//  VultisigAppTests
//
//  Records every call made through `SendInteractor` so tests can assert on
//  ordering, argument forwarding (e.g., `feeMode` threading), and return
//  values. Each method has a stubbable closure and falls back to a sensible
//  default if left unset.
//

import BigInt
import Foundation
import VultisigCommonData
@testable import VultisigApp

// `async` on every method below is required by the `SendInteractor` protocol —
// these mock impls don't actually await anything, so SwiftLint's
// `async_without_await` rule fires. Section-disabled to keep the mock
// readable; same pattern as `MockBalanceService`.

// swiftlint:disable async_without_await

/// Records calls + lets tests stub each protocol method's return value.
@MainActor
final class MockSendInteractor: SendInteractor {

    // MARK: - Call records

    struct FetchChainSpecificCall: Equatable {
        let coin: Coin
        let toAddress: String
        let amount: BigInt
        let memo: String?
        let sendMaxAmount: Bool
        let isDeposit: Bool
        let transactionType: VSTransactionType
        let gasLimit: BigInt?
        let feeMode: FeeMode
        let fromAddress: String
    }

    struct CalculateEVMFeeCall: Equatable {
        let coin: Coin
        let fromAddress: String
        let feeMode: FeeMode
    }

    struct BuildKeysignPayloadCall {
        let coin: Coin
        let toAddress: String
        let amount: BigInt
        let memo: String?
        let chainSpecific: BlockChainSpecific
        let wasmExecuteContractPayload: WasmExecuteContractPayload?
        let vault: Vault
    }

    private(set) var loadFastVaultCalls: [Vault] = []
    private(set) var fetchChainSpecificCalls: [FetchChainSpecificCall] = []
    private(set) var calculateEVMFeeCalls: [CalculateEVMFeeCall] = []
    private(set) var buildKeysignPayloadCalls: [BuildKeysignPayloadCall] = []
    private(set) var updateBalanceCalls: [Coin] = []

    // MARK: - Stubs

    var loadFastVaultResult: Bool = false
    var fetchChainSpecificStub: ((FetchChainSpecificCall) throws -> BlockChainSpecific) = { _ in
        // Sensible default: a Cosmos-shaped chain specific with zero fees.
        .Cosmos(accountNumber: 0, sequence: 0, gas: .zero, transactionType: 0, ibcDenomTrace: nil)
    }
    var calculateEVMFeeStub: ((CalculateEVMFeeCall) throws -> SendInteractorFeeResult) = { _ in
        SendInteractorFeeResult(fee: .zero, gas: .zero)
    }
    var buildKeysignPayloadStub: ((BuildKeysignPayloadCall) throws -> KeysignPayload)?

    // MARK: - Conformance

    func loadFastVault(vault: Vault) async -> Bool {
        loadFastVaultCalls.append(vault)
        return loadFastVaultResult
    }

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
    ) async throws -> BlockChainSpecific {
        let call = FetchChainSpecificCall(
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
        fetchChainSpecificCalls.append(call)
        return try fetchChainSpecificStub(call)
    }

    func calculateEVMFee(
        coin: Coin,
        fromAddress: String,
        feeMode: FeeMode
    ) async throws -> SendInteractorFeeResult {
        let call = CalculateEVMFeeCall(coin: coin, fromAddress: fromAddress, feeMode: feeMode)
        calculateEVMFeeCalls.append(call)
        return try calculateEVMFeeStub(call)
    }

    func buildKeysignPayload(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        chainSpecific: BlockChainSpecific,
        wasmExecuteContractPayload: WasmExecuteContractPayload?,
        vault: Vault
    ) async throws -> KeysignPayload {
        let call = BuildKeysignPayloadCall(
            coin: coin,
            toAddress: toAddress,
            amount: amount,
            memo: memo,
            chainSpecific: chainSpecific,
            wasmExecuteContractPayload: wasmExecuteContractPayload,
            vault: vault
        )
        buildKeysignPayloadCalls.append(call)
        if let stub = buildKeysignPayloadStub {
            return try stub(call)
        }
        // Default: produce a minimal payload from the inputs.
        return KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: amount,
            chainSpecific: chainSpecific,
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: vault.pubKeyECDSA,
            vaultLocalPartyID: vault.localPartyID,
            libType: (vault.libType ?? .GG20).toString(),
            wasmExecuteContractPayload: wasmExecuteContractPayload,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )
    }

    func updateBalance(for coin: Coin) async {
        updateBalanceCalls.append(coin)
    }
}

// swiftlint:enable async_without_await
