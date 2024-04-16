//
//  SendCryptoVerifyViewModel.swift
//  VoltixApp
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
    
    func amount(for coin: Coin, tx: SendTransaction) -> Int64 {
        switch coin.chain {
        case .thorChain:
            return tx.amountInSats
        case .ethereum, .avalanche, .bscChain:
            if coin.isNativeToken {
                return tx.amountInGwei
            } else {
                return tx.amountInTokenWeiInt64
            }
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            return tx.amountInSats
        case .gaiaChain:
            return tx.amountInCoinDecimal
        case .solana:
            return tx.amountInLamports
        }
    }
    func validateForm(tx: SendTransaction) async -> KeysignPayload? {
        
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
            }catch{
                print("fail to fetch utxo data from blockchair , error:\(error.localizedDescription)")
            }
        }
        do{
            let chainSpecific = try await blockChainService.fetchSpecific(for: tx.coin)
            let keysignPayloadFactory = KeysignPayloadFactory()
            keysignPayload = try await keysignPayloadFactory.buildTransfer(coin: tx.coin, 
                                                                           toAddress: tx.fromAddress,
                                                                           amount: amount(for:tx.coin,tx:tx),
                                                                           memo: tx.memo,
                                                                           chainSpecific: chainSpecific)
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
