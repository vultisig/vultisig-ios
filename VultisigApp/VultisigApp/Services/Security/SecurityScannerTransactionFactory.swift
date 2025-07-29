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
            let tokenAmount = BigInt(transaction.amount) ?? .zero
            transferType = SecurityTransactionType.tokenTransfer
            amount = BigInt.zero
            data = try EthereumFunction.transferErc20Encoder(address: transaction.toAddress, amount: tokenAmount)
            to = transaction.coin.contractAddress
        } else {
            transferType = SecurityTransactionType.coinTransfer
            amount = BigInt(transaction.amount) ?? .zero
            data = "0x"
            to = transaction.toAddress
        }
        
        return SecurityScannerTransaction(
            chain: transaction.coin.chain,
            type: transferType,
            from: transaction.toAddress,
            to: to,
            amount: amount,
            data: data
        )
    }
    
    func createSOLSecurityScanner(transaction: SendTransaction) async throws -> SecurityScannerTransaction {
        let vaultHexPubKey = Base58.decodeNoCheck(string: transaction.fromAddress)?.toHexString() ?? .empty
        //        val solanaHelper = SolanaHelper(vaultHexPubKey)
        
        
        var blockchainSpecific: BlockChainSpecific = try await BlockChainService.shared.fetchSpecific(tx: transaction)
        let type: SecurityTransactionType
        
        if transaction.coin.isNativeToken {
            type = .coinTransfer
        } else {
            type = .tokenTransfer
            guard case let .Solana(recentBlockHash, priorityFee, fromAddressPubKey, toAddressPubKey, hasProgramId) = blockchainSpecific else {
                fatalError()
            }
            blockchainSpecific = BlockChainSpecific.Solana(
                recentBlockHash: recentBlockHash,
                priorityFee: priorityFee,
                // TODO: - Check
                fromAddressPubKey: fromAddressPubKey,
                toAddressPubKey: toAddressPubKey,
                hasProgramId: hasProgramId
            )
        }
        
        let keysignPayload = KeysignPayload(
            coin: transaction.coin,
            toAddress: transaction.toAddress,
            toAmount: BigInt(transaction.amount) ?? .zero,
            chainSpecific: blockchainSpecific,
            utxos: [],
            memo: transaction.memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "", // no need for SOL prehash
            vaultLocalPartyID: "", // no need for SOL prehash
            libType: .empty, // no need for SOL prehash
        )
        
        let transactionZeroX = try SolanaHelper.getZeroSignedTransaction(vaultHexPublicKey: vaultHexPubKey, keysignPayload: keysignPayload)
        //
        return SecurityScannerTransaction(
            chain: transaction.coin.chain,
            type: type,
            from: transaction.fromAddress,
            to: transaction.toAddress,
            amount: BigInt.zero, // encoded in tx
            data: transactionZeroX,
        )
    }
    
    func createSUISecurityScanner(transaction: SendTransaction, vault: Vault) async throws -> SecurityScannerTransaction {
        var specific = try await BlockChainService.shared.fetchSpecific(tx: transaction)
        guard case let .Sui(referenceGasPrice, specificCoins) = specific else {
            throw HelperError.runtimeError("Error Blockchain Specific is not SUI")
        }
        
        let coins = !specificCoins.isEmpty ? specificCoins : try await SuiService.shared.getAllCoins(coin: transaction.coin)
        specific = BlockChainSpecific.Sui(
            referenceGasPrice: referenceGasPrice,
            coins: coins,
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
            data: serializedTransaction,
        )
    }
    
    // TODO: Review as it looks like it requires PSBT, which is not supported by WC legacy API
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
        let preHash = try UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: "", vaultHexChainCode: "").getPreSignedImageHash(keysignPayload: keySignPayload)
        
        return SecurityScannerTransaction(
            chain: transaction.coin.chain,
            type: SecurityTransactionType.coinTransfer,
            from: transaction.fromAddress,
            to: transaction.toAddress,
            amount: BigInt.zero,
            data: preHash[0],
        )
    }
}

// MARK: - Swap Transactions

private extension SecurityScannerTransactionFactory {
    func createEVMSecurityScanner(transaction: SwapTransaction) async throws -> SecurityScannerTransaction {
        switch transaction.quote {
        case .oneinch(let quote, _):
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
        case .lifi, .mayachain, .thorchain, .none:
            throw SecurityScannerTransactionFactoryError.swapProviderNotSupported
        }
    }
    
    func buildSwapSecurityScannerTransaction(
        srcToken: Coin,
        from: String,
        to: String,
        amount: String,
        data: String,
        isApprovalRequired: Bool,
    ) throws -> SecurityScannerTransaction {
        let chain = srcToken.chain
        
        if isApprovalRequired {
            return SecurityScannerTransaction(
                chain: chain,
                type: SecurityTransactionType.swap,
                from: from,
                to: srcToken.contractAddress,
                amount: BigInt.zero,
                data: try EthereumFunction.approvalErc20Encoder(address: to, amount: BigInt(amount) ?? .zero),
            )
        } else {
            return SecurityScannerTransaction(
                chain: chain,
                type: SecurityTransactionType.swap,
                from: from,
                to: to,
                amount: BigInt(amount) ?? .zero,
                data: data,
            )
        }
    }
}
