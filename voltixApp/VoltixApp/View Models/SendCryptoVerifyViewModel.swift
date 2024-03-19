//
//  SendCryptoVerifyViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-19.
//

import SwiftUI
import BigInt

@MainActor
class SendCryptoVerifyViewModel: ObservableObject {
    @Published var isAddressCorrect = false
    @Published var isAmountCorrect = false
    @Published var isHackedOrPhished = false
    @Published var showAlert = false
    @Published var errorMessage = ""
    
    @StateObject var thor = ThorchainService.shared
    @StateObject var sol: SolanaService = SolanaService.shared
    
    private var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect && isHackedOrPhished
    }
    
    private func reloadTransactions(tx: SendTransaction, utxoBtc: BitcoinUnspentOutputsService, utxoLtc: LitecoinUnspentOutputsService, eth: EthplorerAPIService) {
        if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
            if utxoBtc.walletData == nil {
                Task {
                    await utxoBtc.fetchUnspentOutputs(for: tx.fromAddress)
                }
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
            if utxoLtc.walletData == nil {
                Task {
                    await utxoLtc.fetchLitecoinUnspentOutputs(for: tx.fromAddress)
                }
            }
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            Task {
                await thor.fetchAccountNumber(tx.fromAddress)
            }
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            Task {
                await sol.getSolanaBalance(account: tx.fromAddress)
                await sol.fetchRecentBlockhash()
                
                if let feeInLamports = sol.feeInLamports {
                    tx.gas = String(feeInLamports)
                }
            }
        }
    }
    
    private func estimateGasForEthTransfer(tx: SendTransaction, web3Service: Web3Service) async -> BigInt {
        do {
            let estimatedGas = try await web3Service.estimateGasForEthTransaction(senderAddress: tx.fromAddress, recipientAddress: tx.toAddress, value: tx.amountInWei, memo: tx.memo)
            
            print("Estimated gas: \(estimatedGas)")
            
            return estimatedGas
        } catch {
            errorMessage = "Error estimating gas: \(error.localizedDescription)"
            showAlert = true
        }
        return 0
    }
    
    private func estimateGasForERC20Transfer(tx: SendTransaction, web3Service: Web3Service) async -> BigInt {
        
        let decimals: Double = Double(tx.token?.tokenInfo.decimals ?? "18") ?? 18
        
        let amountInSmallestUnit: Double = tx.amountDecimal * pow(10.0, decimals)
        
        let value = BigInt(amountInSmallestUnit)
        
        do {
            let estimatedGas = try await web3Service.estimateGasForERC20Transfer(senderAddress: tx.fromAddress, contractAddress: tx.coin.contractAddress, recipientAddress: tx.toAddress, value: value)
            
            print("Estimated gas: \(estimatedGas)")
            
            return estimatedGas
        } catch {
            errorMessage = "Error estimating gas: \(error.localizedDescription)"
            showAlert = true
        }
        return 0
    }
}
