//
//  SendCryptoVerifyViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-19.
//

import SwiftUI
import BigInt
import WalletCore

@MainActor
class SendCryptoVerifyViewModel: ObservableObject {
    
    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var isHackedOrPhished = false
    @Published var showAlert = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    @Published var blowfishShow = false
    @Published var blowfishWarningsShow = false
    @Published var blowfishWarnings: [String] = []
    
    @Published var thor = ThorchainService.shared
    @Published var sol: SolanaService = SolanaService.shared
    @Published var utxo = BlockchairService.shared
    @Published var eth = EthService.shared
    var gaia = GaiaService.shared
    let blockChainService = BlockChainService.shared
    
    var THORChainAccount: THORChainAccountValue? = nil
    var CosmosChainAccount: CosmosAccountValue? = nil
    
    private var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect && isHackedOrPhished
    }
    
    func amount(for coin: Coin, tx: SendTransaction) -> BigInt {
        return tx.amountInRaw
    }
    
    func blowfishTransactionScan(tx: SendTransaction, vault: Vault) async throws {
        
        switch tx.coin.chain.chainType {
        case .EVM:
            let blowfishResponse = try await blowfishEVMTransactionScan(tx: tx)
            blowfishShow = true
            blowfishWarningsShow = !(blowfishResponse.warnings?.isEmpty ?? true)
            blowfishWarnings = blowfishResponse.warnings?.compactMap { $0.message } ?? []
            
        case .Solana:
            let blowfishResponse = try await blowfishSolanaTransactionScan(tx: tx, vault: vault)
            blowfishShow = true
            blowfishWarningsShow = !(blowfishResponse.aggregated?.warnings?.isEmpty ?? true)
            blowfishWarnings = blowfishResponse.aggregated?.warnings?.compactMap { $0.message } ?? []
            
        default:
            blowfishShow = false
            blowfishWarningsShow = false
            blowfishWarnings = []
            
        }
        
    }
    
    func blowfishEVMTransactionScan(tx: SendTransaction) async throws -> BlowfishResponse {
        
        return try await BlowfishService.shared.blowfishEVMTransactionScan(
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            amountInRaw: tx.amountInRaw,
            memo: tx.memo,
            chain: tx.coin.chain
        )
        
    }
    
    func blowfishSolanaTransactionScan(tx: SendTransaction, vault: Vault) async throws -> BlowfishResponse {
        
        let chainSpecific = try await blockChainService.fetchSpecific(
            for: tx,
            sendMaxAmount: tx.sendMaxAmount,
            isDeposit: tx.isDeposit,
            transactionType: tx.transactionType
        )
        
        let keysignPayloadFactory = KeysignPayloadFactory()
        
        let keysignPayload = try await keysignPayloadFactory.buildTransfer(coin: tx.coin,
                                                                           toAddress: tx.toAddress,
                                                                           amount: amount(for:tx.coin,tx:tx),
                                                                           memo: tx.memo,
                                                                           chainSpecific: chainSpecific,
                                                                           vault: vault
        )
        
        let zeroSignedTransaction: String = try SolanaHelper.getZeroSignedTransaction(
            vaultHexPubKey: vault.pubKeyEdDSA,
            vaultHexChainCode: vault.hexChainCode,
            keysignPayload: keysignPayload
        )
        
        return try await BlowfishService.shared.blowfishSolanaTransactionScan(
            fromAddress: tx.fromAddress, zeroSignedTransaction: zeroSignedTransaction
        )
        
    }
    
    func validateForm(tx: SendTransaction, vault: Vault) async -> KeysignPayload? {
        defer {
            isLoading = false
        }
        
        if !isValidForm {
            self.errorMessage = "mustAgreeTermsError"
            showAlert = true
            return nil
        }
        
        var keysignPayload: KeysignPayload?
        
        if tx.coin.chain.chainType == ChainType.UTXO {
            do {
                _ = try await utxo.fetchBlockchairData(coin: tx.coin)
            } catch {
                print("fail to fetch utxo data from blockchair , error:\(error.localizedDescription)")
            }
        }
        
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(
                for: tx,
                sendMaxAmount: tx.sendMaxAmount,
                isDeposit: tx.isDeposit,
                transactionType: tx.transactionType
            )
            
            let keysignPayloadFactory = KeysignPayloadFactory()
            keysignPayload = try await keysignPayloadFactory.buildTransfer(coin: tx.coin,
                                                                           toAddress: tx.toAddress,
                                                                           amount: amount(for:tx.coin,tx:tx),
                                                                           memo: tx.memo,
                                                                           chainSpecific: chainSpecific,
                                                                           vault: vault
            )
            
        } catch {
            self.errorMessage = error.localizedDescription
            showAlert = true
            return nil
        }
        return keysignPayload
    }
}
