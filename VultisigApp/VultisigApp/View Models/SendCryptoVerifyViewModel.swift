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
    
    @Published var showBlowfish = false
    @Published var ShowBlowfishWarnings = false
    
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
    
    func blowfishTransactionScan(tx: SendTransaction, vault: Vault) async -> BlowfishResponse? {
        
        switch tx.coin.chain.chainType {
        case .EVM:
            let blowfishResponse = await blowfishEVMTransactionScan(tx: tx)
            showBlowfish = blowfishResponse != nil
            ShowBlowfishWarnings = blowfishResponse != nil && !(blowfishResponse?.warnings?.isEmpty ?? true)
            return blowfishResponse
        case .Solana:
            let blowfishResponse = await blowfishSolanaTransactionScan(tx: tx, vault: vault)
            showBlowfish = blowfishResponse != nil
            ShowBlowfishWarnings = blowfishResponse != nil && !(blowfishResponse?.aggregated?.warnings?.isEmpty ?? true)
            return blowfishResponse
        default:
            return nil
        }
        
    }
    
    func blowfishEVMTransactionScan(tx: SendTransaction) async -> BlowfishResponse? {
        return await BlowfishService.shared.blowfishEVMTransactionScan(
            fromAddress: tx.fromAddress, toAddress: tx.toAddress, amountInRaw: tx.amountInRaw, memo: tx.memo, chain: tx.coin.chain
        )
    }
    
    func blowfishSolanaTransactionScan(tx: SendTransaction, vault: Vault) async -> BlowfishResponse? {
        
        var keysignPayload: KeysignPayload?
        
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(for: tx, sendMaxAmount: tx.sendMaxAmount, isDeposit: tx.isDeposit, transactionType: tx.transactionType)
            let keysignPayloadFactory = KeysignPayloadFactory()
            keysignPayload = try await keysignPayloadFactory.buildTransfer(coin: tx.coin,
                                                                           toAddress: tx.toAddress,
                                                                           amount: amount(for:tx.coin,tx:tx),
                                                                           memo: tx.memo,
                                                                           chainSpecific: chainSpecific,
                                                                           vault: vault
            )
            
            
            var zeroSignedTransaction: String = .empty
            if let payload = keysignPayload {
                zeroSignedTransaction = try SolanaHelper.getZeroSignedTransaction(vaultHexPubKey: vault.pubKeyEdDSA, vaultHexChainCode: vault.hexChainCode, keysignPayload: payload)
                
            }
            
            
            return await BlowfishService.shared.blowfishSolanaTransactionScan(
                fromAddress: tx.fromAddress, zeroSignedTransaction: zeroSignedTransaction
            )
            
        } catch {
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughBalanceError:
                self.errorMessage = "notEnoughBalanceError"
            case KeysignPayloadFactory.Errors.failToGetSequenceNo:
                self.errorMessage = "failToGetSequenceNo"
            case KeysignPayloadFactory.Errors.failToGetAccountNumber:
                self.errorMessage = "failToGetAccountNumber"
            case KeysignPayloadFactory.Errors.failToGetRecentBlockHash:
                self.errorMessage = "failToGetRecentBlockHash"
            default:
                self.errorMessage = error.localizedDescription
            }
            showAlert = true
            isLoading = false
            return nil
        }
    }
    
    func validateForm(tx: SendTransaction, vault: Vault) async -> KeysignPayload? {
        
        if !isValidForm {
            self.errorMessage = "mustAgreeTermsError"
            showAlert = true
            isLoading = false
            return nil
        }
        
        var keysignPayload: KeysignPayload?
        
        if tx.coin.chain.chainType == ChainType.UTXO {
            
            do{
                _ = try await utxo.fetchBlockchairData(coin: tx.coin)
            } catch {
                print("fail to fetch utxo data from blockchair , error:\(error.localizedDescription)")
            }
        }
        
        do {
            let chainSpecific = try await blockChainService.fetchSpecific(for: tx, sendMaxAmount: tx.sendMaxAmount, isDeposit: tx.isDeposit, transactionType: tx.transactionType)
            let keysignPayloadFactory = KeysignPayloadFactory()
            keysignPayload = try await keysignPayloadFactory.buildTransfer(coin: tx.coin,
                                                                           toAddress: tx.toAddress,
                                                                           amount: amount(for:tx.coin,tx:tx),
                                                                           memo: tx.memo,
                                                                           chainSpecific: chainSpecific, vault: vault)
        } catch {
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughBalanceError:
                self.errorMessage = "notEnoughBalanceError"
            case KeysignPayloadFactory.Errors.failToGetSequenceNo:
                self.errorMessage = "failToGetSequenceNo"
            case KeysignPayloadFactory.Errors.failToGetAccountNumber:
                self.errorMessage = "failToGetAccountNumber"
            case KeysignPayloadFactory.Errors.failToGetRecentBlockHash:
                self.errorMessage = "failToGetRecentBlockHash"
            default:
                self.errorMessage = error.localizedDescription
            }
            showAlert = true
            isLoading = false
            return nil
        }
        return keysignPayload
    }
}
