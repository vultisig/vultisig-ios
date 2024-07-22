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
    
    func blowfishEVMTransactionScan(tx: SendTransaction) async throws -> BlowfishResponse? {
        
        let amountDataHex = tx.amountInRaw.serializeForEvm().map { byte in String(format: "%02x", byte) }.joined()
        let amount = "0x" + amountDataHex
        
        let txObjects = [
            BlowfishRequest.BlowfishTxObject(
                from: tx.fromAddress,
                to: tx.toAddress,
                value: amount,
                data: nil
            )
        ]
        
        let response = try await BlowfishService.shared.scanTransactions(
            chain: tx.coin.chain,
            userAccount: tx.fromAddress,
            origin: "https://api.vultisig.com",
            txObjects: txObjects
        )
        
        return response
        
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
            let chainSpecific = try await blockChainService.fetchSpecific(for: tx, sendMaxAmount: tx.sendMaxAmount)
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
