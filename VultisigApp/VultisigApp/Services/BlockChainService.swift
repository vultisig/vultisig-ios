//
//  FeeService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt
import VultisigCommonData

final class BlockChainService {

    static func normalizeUTXOFee(_ value: BigInt, action: Action) -> BigInt {
        return value * 2 + value / 2 // x2.5 fee
    }

    static func normalizeEVMFee(_ value: BigInt, action: Action) -> BigInt {
        return value + value / 2 // x1.5 fee
    }

    enum Action {
        case transfer
        case swap
    }
    
    enum Errors: String, Error, LocalizedError {
        case failToGetAccountNumber
        case failToGetSequenceNo
        case failToGetRecentBlockHash
        
        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }
    
    static let shared = BlockChainService()
    
    private let utxo = BlockchairService.shared
    private let sol = SolanaService.shared
    private let sui = SuiService.shared
    private let dot = PolkadotService.shared
    private let thor = ThorchainService.shared
    private let atom = GaiaService.shared
    private let maya = MayachainService.shared
    private let kuji = KujiraService.shared
    private let dydx = DydxService.shared
    private let ton = TonService.shared

    func fetchSpecific(tx: SendTransaction) async throws -> BlockChainSpecific {
        guard !tx.coin.isNativeToken, tx.coin.chainType == .EVM else {
            let specific = try await fetchSpecific(
                for: tx.coin,
                action: .transfer,
                sendMaxAmount: tx.sendMaxAmount,
                isDeposit: tx.isDeposit,
                transactionType: tx.transactionType, 
                gasLimit: tx.gasLimit,
                fromAddress: tx.fromAddress,
                toAddress: tx.toAddress,
                feeMode: tx.feeMode
            )
            return specific
        }

        let service = try EvmServiceFactory.getService(forChain: tx.coin.chain)
        let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: tx.coin.address, mode: tx.feeMode)
        let estimateGasLimit = try await estemateERC20GasLimit(tx: tx, gasPrice: gasPrice, priorityFee: priorityFee, nonce: nonce)
        let defaultGasLimit = BigInt(EVMHelper.defaultERC20TransferGasUnit)
        let gasLimit = max(defaultGasLimit, estimateGasLimit)

        let specific = try await fetchSpecific(
            for: tx.coin, 
            action: .transfer,
            sendMaxAmount: tx.sendMaxAmount,
            isDeposit: tx.isDeposit,
            transactionType: tx.transactionType,
            gasLimit: max(gasLimit, tx.gasLimit), 
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            feeMode: tx.feeMode
        )

        return specific
    }

    func fetchSpecific(tx: SwapTransaction) async throws -> BlockChainSpecific {
        let specific = try await fetchSpecific(
            for: tx.fromCoin,
            action: .swap,
            sendMaxAmount: false,
            isDeposit: tx.isDeposit,
            transactionType: .unspecified, 
            gasLimit: nil,
            fromAddress: nil,
            toAddress: nil,
            feeMode: .fast
        )

        return specific
    }
}

private extension BlockChainService {

    func fetchSpecific(for coin: Coin, action: Action, sendMaxAmount: Bool, isDeposit: Bool, transactionType: VSTransactionType, gasLimit: BigInt?, fromAddress: String?, toAddress: String?, feeMode: FeeMode) async throws -> BlockChainSpecific {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let sats = try await utxo.fetchSatsPrice(coin: coin)
            let normalized = Self.normalizeUTXOFee(sats, action: action)
            return .UTXO(byteFee: normalized, sendMaxAmount: sendMaxAmount)

        case .thorChain:
            _ = try await thor.getTHORChainChainID()
            let account = try await thor.fetchAccountNumber(coin.address)
            let fee = try await thor.fetchFeePrice()

            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }

            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .THORChain(accountNumber: accountNumber, sequence: sequence, fee: fee, isDeposit: isDeposit)
        case .mayaChain:
            let account = try await maya.fetchAccountNumber(coin.address)

            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }

            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .MayaChain(accountNumber: accountNumber, sequence: sequence, isDeposit: isDeposit)
        case .solana:
            async let recentBlockHashPromise = sol.fetchRecentBlockhash()
            async let highPriorityFeePromise = sol.fetchHighPriorityFee(account: coin.address)

            let recentBlockHash = try await recentBlockHashPromise
            let highPriorityFee = try await highPriorityFeePromise

            guard let recentBlockHash else {
                throw Errors.failToGetRecentBlockHash
            }

            if let fromAddress, let toAddress, !toAddress.isEmpty, !coin.isNativeToken {
                async let associatedTokenAddressFromPromise = sol.fetchTokenAssociatedAccountByOwner(for: fromAddress, mintAddress: coin.contractAddress)
                async let associatedTokenAddressToPromise = sol.fetchTokenAssociatedAccountByOwner(for: toAddress, mintAddress: coin.contractAddress)
                let associatedTokenAddressFrom = try await associatedTokenAddressFromPromise
                let associatedTokenAddressTo = try await associatedTokenAddressToPromise

                return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(highPriorityFee), fromAddressPubKey: associatedTokenAddressFrom, toAddressPubKey: associatedTokenAddressTo)
            }

            return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(highPriorityFee), fromAddressPubKey: nil, toAddressPubKey: nil)

        case .sui:
            let (referenceGasPrice, allCoins) = try await sui.getGasInfo(coin: coin)
            return .Sui(referenceGasPrice: referenceGasPrice, coins: allCoins)

        case .polkadot:
            let gasInfo = try await dot.getGasInfo(fromAddress: coin.address)
            return .Polkadot(recentBlockHash: gasInfo.recentBlockHash, nonce: UInt64(gasInfo.nonce), currentBlockNumber: gasInfo.currentBlockNumber, specVersion: gasInfo.specVersion, transactionVersion: gasInfo.transactionVersion, genesisHash: gasInfo.genesisHash)

        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain:
            let service = try EvmServiceFactory.getService(forChain: coin.chain)
            let baseFee = try await service.getBaseFee()
            let (_, defaultPriorityFee, nonce) = try await service.getGasInfo(fromAddress: coin.address, mode: feeMode)
            let gasLimit = gasLimit ?? normalizeGasLimit(coin: coin, action: action)
            let priorityFeesMap = try await service.fetchMaxPriorityFeesPerGas()
            let priorityFee = priorityFeesMap[feeMode] ?? defaultPriorityFee
            let normalizedBaseFee = Self.normalizeEVMFee(baseFee, action: .transfer)
            let maxFeePerGasWei = normalizedBaseFee + priorityFee
            return .Ethereum(maxFeePerGasWei: maxFeePerGasWei, priorityFeeWei: priorityFee, nonce: nonce, gasLimit: gasLimit)

        case .zksync:
            let service = try EvmServiceFactory.getService(forChain: coin.chain)
            let (gasLimit, _, maxFeePerGas, maxPriorityFeePerGas, nonce) = try await service.getGasInfoZk(fromAddress: coin.address, toAddress: .zeroAddress)

            return .Ethereum(maxFeePerGasWei: maxFeePerGas, priorityFeeWei: maxPriorityFeePerGas, nonce: nonce, gasLimit: gasLimit)

        case .gaiaChain:
            let account = try await atom.fetchAccountNumber(coin.address)

            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }

            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 7500, transactionType: transactionType.rawValue)
        case .kujira:
            let account = try await kuji.fetchAccountNumber(coin.address)

            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }

            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 7500, transactionType: transactionType.rawValue)
        case .dydx:
            let account = try await dydx.fetchAccountNumber(coin.address)

            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }

            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 2500000000000000, transactionType: transactionType.rawValue)
        case .ton:
            let (seqno, expireAt) = try await ton.getSpecificTransactionInfo(coin)
            return .Ton(sequenceNumber: seqno, expireAt: expireAt, bounceable: false)
        }
    }

    func normalizeGasLimit(coin: Coin, action: Action) -> BigInt {
        switch action {
        case .transfer:
            return BigInt(coin.feeDefault) ?? 0
        case .swap:
            return BigInt(EVMHelper.defaultETHSwapGasUnit)
        }
    }

    func normalizePriorityFee(_ value: BigInt,_ chain: Chain) -> BigInt {
        if chain == .ethereum || chain == .avalanche {
            // BSC is very cheap , and layer two is very low priority fee as well
            //  Just pay 1Gwei priority for ETH and AVAX
            let oneGwei = BigInt(1000000000)
            if value < oneGwei {
                return oneGwei
            }
        }
        return value
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
            recipientAddress: .anyAddress,
            value: BigInt(stringLiteral: tx.coin.rawBalance)
        )
        return gas
    }
}
