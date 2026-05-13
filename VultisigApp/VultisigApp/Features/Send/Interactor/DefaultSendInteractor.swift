//
//  DefaultSendInteractor.swift
//  VultisigApp
//
//  Concrete `SendInteractor` wiring. Production builds via `.live` with the
//  existing `.shared` singletons; tests can inject a mock conforming to the
//  protocol.
//

import BigInt
import Foundation
import VultisigCommonData

struct DefaultSendInteractor: SendInteractor {
    let blockchain: BlockChainService
    let balance: BalanceService
    let fastVault: FastVaultService
    let keysignFactory: KeysignPayloadFactory

    static var live: SendInteractor {
        DefaultSendInteractor(
            blockchain: BlockChainService.shared,
            balance: BalanceService.shared,
            fastVault: FastVaultService.shared,
            keysignFactory: KeysignPayloadFactory()
        )
    }

    func loadFastVault(vault: Vault) async -> Bool {
        let exists = await fastVault.exist(pubKeyECDSA: vault.pubKeyECDSA)
        let isLocalBackup = vault.localPartyID.lowercased().hasPrefix("server-")
        return exists && !isLocalBackup
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
        try await blockchain.fetchSendBlockChainSpecific(
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
    }

    func calculateEVMFee(
        coin: Coin,
        fromAddress: String,
        feeMode: FeeMode
    ) async throws -> SendInteractorFeeResult {
        let service = try EthereumFeeService(chain: coin.chain)
        let gasLimit = coin.isNativeToken
            ? BigInt(EVMHelper.defaultETHTransferGasUnit)
            : BigInt(EVMHelper.defaultERC20TransferGasUnit)

        let feeInfo = try await service.calculateFees(
            chain: coin.chain,
            limit: gasLimit,
            isSwap: false,
            fromAddress: fromAddress,
            feeMode: feeMode
        )

        let fee = feeInfo.amount
        let gas: BigInt
        switch feeInfo {
        case let .GasFee(price, _, _, _):
            gas = price
        case let .Eip1559(_, maxFeePerGas, _, _, _):
            gas = maxFeePerGas
        case let .BasicFee(amount, _, limit):
            gas = limit > 0 ? amount / limit : amount
        }

        return SendInteractorFeeResult(fee: fee, gas: gas)
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
        try await keysignFactory.buildTransfer(
            coin: coin,
            toAddress: toAddress,
            amount: amount,
            memo: memo,
            chainSpecific: chainSpecific,
            swapPayload: nil,
            approvePayload: nil,
            vault: vault,
            wasmExecuteContractPayload: wasmExecuteContractPayload
        )
    }

    func updateBalance(for coin: Coin) async {
        await balance.updateBalance(for: coin)
    }
}
