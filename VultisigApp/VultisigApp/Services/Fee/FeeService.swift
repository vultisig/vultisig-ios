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
        let gasLimit = try estemateERC20GasLimit(tx: tx, gasPrice: gasPrice, priorityFee: priorityFee, nonce: nonce)

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
    ) throws -> BigInt {

        guard let chainID = tx.coin.chain.chainID else {
            throw Errors.failToGetChainID
        }

        let input = EthereumSigningInput.with {
            $0.chainID = Data(hexString: Int64(chainID).hexString())!
            $0.nonce = Data(hexString: nonce.hexString())!
            $0.maxFeePerGas = gasPrice.magnitude.serialize()
            $0.maxInclusionFeePerGas = priorityFee.magnitude.serialize()
            $0.toAddress = tx.coin.contractAddress
            $0.txMode = .enveloped
            $0.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = tx.toAddress
                    $0.amount = tx.amountInRaw.serializeForEvm()
                }
            }
        }

        fatalError(input.debugDescription)
    }
}

private extension FeeService {

    enum Errors: Error {
        case failToGetChainID
    }
}
