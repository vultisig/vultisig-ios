//
//  SecurityScannerTransactionFactory.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import WalletCore
import BigInt

enum SecurityScannerTransactionFactoryError: Error {
    case notSupported(chain: Chain)
    case swapProviderNotSupported
    case invalidAddress(String)
    case invalidBlockchainSpecific(String)
}

struct SecurityScannerTransactionFactory: SecurityScannerTransactionFactoryProtocol {
    func createSecurityScanner(transaction: SendTransaction, vault: Vault) async throws -> SecurityScannerTransaction {
        let chain = transaction.coin.chain
        switch chain.chainType {
        case .EVM:
            return try createEVMSecurityScanner(transaction: transaction)
        case .Solana:
            return try await createSOLSecurityScanner(transaction: transaction)
        case .Sui:
            return try await createSUISecurityScanner(transaction: transaction, vault: vault)
        case .UTXO:
            return try await createBTCSecurityScanner(transaction: transaction, vault: vault)
        default:
            throw SecurityScannerTransactionFactoryError.notSupported(chain: chain)
        }
    }
    
    func createSecurityScanner(transaction: SwapTransaction) async throws -> SecurityScannerTransaction {
        let chain = transaction.fromCoin.chain
        switch chain.chainType {
        case .EVM:
            return try await createEVMSecurityScanner(transaction: transaction)
        default:
            throw SecurityScannerTransactionFactoryError.notSupported(chain: chain)
        }
    }
}

// MARK: - Send Transactions

private extension SecurityScannerTransactionFactory {
    func createEVMSecurityScanner(transaction: SendTransaction) throws -> SecurityScannerTransaction {
        let transferType: SecurityTransactionType
        let amount: BigInt
        let data: String
        let to: String
        
        if (!transaction.coin.isNativeToken) {
            let tokenAmount = transaction.amountInRaw
            transferType = SecurityTransactionType.tokenTransfer
            amount = BigInt.zero
            data = try EthereumFunction.transferErc20Encoder(address: transaction.toAddress, amount: tokenAmount)
            to = transaction.coin.contractAddress
        } else {
            transferType = SecurityTransactionType.coinTransfer
            amount = transaction.amountInRaw
            data = "0x"
            to = transaction.toAddress
        }
        
        return SecurityScannerTransaction(
            chain: transaction.coin.chain,
            type: transferType,
            from: transaction.fromAddress,
            to: to,
            amount: amount,
            data: data
        )
    }
    
    func createSOLSecurityScanner(transaction: SendTransaction) async throws -> SecurityScannerTransaction {
        guard let _ = Base58.decodeNoCheck(string: transaction.fromAddress) else {
            throw SecurityScannerTransactionFactoryError.invalidAddress(transaction.fromAddress)
        }
        var blockchainSpecific: BlockChainSpecific = try await BlockChainService.shared.fetchSpecific(tx: transaction)
        let type: SecurityTransactionType
        
        if transaction.coin.isNativeToken {
            type = .coinTransfer
        } else {
            type = .tokenTransfer
            guard case let .Solana(recentBlockHash, priorityFee, priorityLimit, fromAddressPubKey, toAddressPubKey, hasProgramId) = blockchainSpecific else {
                throw SecurityScannerTransactionFactoryError.invalidBlockchainSpecific("Expected Solana specific data")
            }
            blockchainSpecific = BlockChainSpecific.Solana(
                recentBlockHash: recentBlockHash,
                priorityFee: priorityFee,
                priorityLimit: priorityLimit,
                fromAddressPubKey: fromAddressPubKey,
                toAddressPubKey: toAddressPubKey,
                hasProgramId: hasProgramId
            )
        }
        
        let keysignPayload = KeysignPayload(
            coin: transaction.coin,
            toAddress: transaction.toAddress,
            toAmount: transaction.amountInRaw,
            chainSpecific: blockchainSpecific,
            utxos: [],
            memo: transaction.memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "", // no need for SOL prehash
            vaultLocalPartyID: "", // no need for SOL prehash
            libType: .empty, // no need for SOL prehash
            wasmExecuteContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )
        
        let transactionZeroX = try SolanaHelper.getZeroSignedTransaction(keysignPayload: keysignPayload)
        
        return SecurityScannerTransaction(
            chain: transaction.coin.chain,
            type: type,
            from: transaction.fromAddress,
            to: transaction.toAddress,
            amount: BigInt.zero, // encoded in tx
            data: transactionZeroX
        )
    }
    
    func createSUISecurityScanner(transaction: SendTransaction, vault: Vault) async throws -> SecurityScannerTransaction {
        var specific = try await BlockChainService.shared.fetchSpecific(tx: transaction)
        guard case let .Sui(referenceGasPrice, specificCoins, gasBudget) = specific else {
            throw HelperError.runtimeError("Error Blockchain Specific is not SUI")
        }
        
        let coins = !specificCoins.isEmpty ? specificCoins : try await SuiService.shared.getAllCoins(coin: transaction.coin)
        specific = BlockChainSpecific.Sui(
            referenceGasPrice: referenceGasPrice,
            coins: coins,
            gasBudget: gasBudget
        )
        
        let keySignPayload = try await KeysignPayloadFactory().buildTransfer(
            coin: transaction.coin,
            toAddress: transaction.toAddress,
            amount: transaction.amountInRaw,
            memo: transaction.memo,
            chainSpecific: specific,
            vault: vault
        )
        let serializedTransaction = try SuiHelper.getZeroSignedTransaction(keysignPayload: keySignPayload)
        
        return SecurityScannerTransaction(
            chain: transaction.coin.chain,
            type: SecurityTransactionType.coinTransfer,
            from: transaction.fromAddress,
            to: transaction.toAddress,
            amount: BigInt.zero,
            data: serializedTransaction
        )
    }
    
    func createBTCSecurityScanner(transaction: SendTransaction, vault: Vault) async throws -> SecurityScannerTransaction {
        let specific = try await BlockChainService.shared.fetchSpecific(tx: transaction)
        let keySignPayload = try await KeysignPayloadFactory().buildTransfer(
            coin: transaction.coin,
            toAddress: transaction.toAddress,
            amount: transaction.amountInRaw,
            memo: transaction.memo,
            chainSpecific: specific,
            vault: vault
        )
        
        
        let inputData = try UTXOChainsHelper(coin: .bitcoin).getUnsignedTransactionHex(keysignPayload: keySignPayload)
        
        return SecurityScannerTransaction(
            chain: transaction.coin.chain,
            type: SecurityTransactionType.coinTransfer,
            from: transaction.fromAddress,
            to: transaction.toAddress,
            amount: transaction.amountInRaw,
            data: inputData
        )
    }
}

// MARK: - Swap Transactions

private extension SecurityScannerTransactionFactory {
    func createEVMSecurityScanner(transaction: SwapTransaction) async throws -> SecurityScannerTransaction {
        switch transaction.quote {
        case .oneinch(let quote, _), .lifi(let quote, _, _):
            try buildSwapSecurityScannerTransaction(
                srcToken: transaction.fromCoin,
                from: quote.tx.from,
                to: quote.tx.to,
                amount: quote.tx.value,
                data: quote.tx.data,
                isApprovalRequired: transaction.isApproveRequired
            )
        case .kyberswap(let quote, _):
            try buildSwapSecurityScannerTransaction(
                srcToken: transaction.fromCoin,
                from: quote.tx.from,
                to: quote.tx.to,
                amount: quote.tx.value,
                data: quote.tx.data,
                isApprovalRequired: transaction.isApproveRequired
            )
        case .mayachain, .thorchain, .thorchainStagenet, .none:
            throw SecurityScannerTransactionFactoryError.swapProviderNotSupported
        }
    }
    
    func buildSwapSecurityScannerTransaction(
        srcToken: Coin,
        from: String,
        to: String,
        amount: String,
        data: String,
        isApprovalRequired: Bool
    ) throws -> SecurityScannerTransaction {
        let chain = srcToken.chain
        
        if isApprovalRequired {
            return SecurityScannerTransaction(
                chain: chain,
                type: SecurityTransactionType.swap,
                from: from,
                to: srcToken.contractAddress,
                amount: BigInt.zero,
                data: try EthereumFunction.approvalErc20Encoder(address: to, amount: BigInt(amount) ?? .zero)
            )
        } else {
            return SecurityScannerTransaction(
                chain: chain,
                type: SecurityTransactionType.swap,
                from: from,
                to: to,
                amount: BigInt(amount) ?? .zero,
                data: data
            )
        }
    }
}
