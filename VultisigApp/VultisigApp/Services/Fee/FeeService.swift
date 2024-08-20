//
//  FeeService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 20.08.2024.
//

import Foundation
import BigInt
import WalletCore

struct FeeService {

    static let shared = FeeService()

    private let blockchainService = BlockChainService.shared

    func fetchFee(tx: SendTransaction) async throws -> BigInt {
        guard !tx.coin.isNativeToken, tx.coin.chainType == .EVM else {
            return try await blockchainService.fetchSpecific(
                for: tx.coin, sendMaxAmount: false,
                isDeposit: tx.isDeposit,
                transactionType: tx.transactionType
            ).fee
        }

        let service = try EvmServiceFactory.getService(forChain: tx.coin.chain)
        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: tx.coin.address)
        let gasLimit = try await estemateERC20GasLimit(tx: tx, gasPrice: gasPrice, priorityFee: priorityFee, nonce: nonce)

        return try await blockchainService.fetchSpecific(
            for: tx.coin, sendMaxAmount: false,
            isDeposit: tx.isDeposit,
            transactionType: tx.transactionType,
            gasLimit: gasLimit
        ).fee
    }

    func estemateERC20GasLimit(
        tx: SendTransaction,
        gasPrice: BigInt,
        priorityFee: BigInt,
        nonce: Int64
    ) async throws -> BigInt {
        let service = try EvmServiceFactory.getService(forChain: tx.coin.chain)
        let gas = try await service.estimateGasForERC20Transfer(
            senderAddress: tx.coin.address,
            contractAddress: tx.coin.contractAddress,
            recipientAddress: tx.toAddress,
            value: tx.amountInRaw
        )
        return gas
    }
}

private extension FeeService {

    enum Errors: Error {
        case failToGetChainID
    }
}
