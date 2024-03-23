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
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    @Published var thor = ThorchainService.shared
    @Published var sol: SolanaService = SolanaService.shared
    @Published var utxo = BlockchairService.shared
	@Published var eth = EtherScanService.shared
	
    
    var THORChainAccount: ThorchainAccountValue? = nil
    private var isValidForm: Bool {
        return isAddressCorrect && isAmountCorrect && isHackedOrPhished
    }
    
    func reloadTransactions(tx: SendTransaction) {
        Task {
            if  tx.coin.chain.chainType == ChainType.UTXO {
                await utxo.fetchBlockchairData(for: tx.fromAddress, coinName: tx.coin.chain.name.lowercased())
            } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
                self.THORChainAccount = try await thor.fetchAccountNumber(tx.fromAddress)
            } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
                
                await sol.getSolanaBalance(account: tx.fromAddress)
                await sol.fetchRecentBlockhash()
                
                await MainActor.run {
                    if let feeInLamports = sol.feeInLamports {
                        tx.gas = String(feeInLamports)
                    }
                }
                
            }
        }
    }
    
    private func estimateGasForEthTransfer(tx: SendTransaction) async -> BigInt {
        do {
			let estimatedGas = try await eth.estimateGasForEthTransaction(senderAddress: tx.fromAddress, recipientAddress: tx.toAddress, value: tx.amountInWei, memo: tx.memo)
            
            print("Estimated gas: \(estimatedGas)")
            
            return estimatedGas
        } catch {
            errorMessage = "\(NSLocalizedString("gasEstimateError:", comment: "")) \(error.localizedDescription)"
            showAlert = true
            isLoading = false
        }
        return 0
    }
    
    private func estimateGasForERC20Transfer(tx: SendTransaction) async -> BigInt {
        
        let decimals: Double = Double(tx.token?.tokenInfo.decimals ?? "18") ?? 18
        
        let amountInSmallestUnit: Double = tx.amountDecimal * pow(10.0, decimals)
        
        let value = BigInt(amountInSmallestUnit)
        
        do {
            let estimatedGas = try await eth.estimateGasForERC20Transfer(senderAddress: tx.fromAddress, contractAddress: tx.coin.contractAddress, recipientAddress: tx.toAddress, value: value)
            
            print("Estimated gas: \(estimatedGas)")
            
            return estimatedGas
        } catch {
            errorMessage = "\(NSLocalizedString("gasEstimateError:", comment: "")) \(error.localizedDescription)"
            showAlert = true
            isLoading = false
        }
        return 0
    }
    
    func validateForm(tx: SendTransaction) async -> KeysignPayload? {
        
        
        if !isValidForm {
            self.errorMessage = "mustAgreeTermsError"
            showAlert = true
            isLoading = false
            return nil
        }
        
        if tx.coin.chain.chainType == ChainType.UTXO {
            
            let coinName = tx.coin.chain.name.lowercased()
            let key: String = "\(tx.fromAddress)-\(coinName)"
            
            let totalAmountNeeded = tx.amountInSats + tx.feeInSats
            
            guard let utxoInfo = utxo.blockchairData[key]?.selectUTXOsForPayment(amountNeeded: Int64(totalAmountNeeded)).map({
                UtxoInfo(
                    hash: $0.transactionHash ?? "",
                    amount: Int64($0.value ?? 0),
                    index: UInt32($0.index ?? -1)
                )
            }), !utxoInfo.isEmpty else {
                self.errorMessage = "notEnoughBalanceError"
                showAlert = true
                isLoading = false
                return nil
            }
            
            let totalSelectedAmount = utxoInfo.reduce(0) { $0 + $1.amount }
            
            if totalSelectedAmount < Int64(totalAmountNeeded) {
                self.errorMessage = "notEnoughBalanceError"
                showAlert = true
                isLoading = false
                return nil
            }
            
            let keysignPayload = KeysignPayload(
                coin: tx.coin,
                toAddress: tx.toAddress,
                toAmount: tx.amountInSats,
                chainSpecific: BlockChainSpecific.UTXO(byteFee: tx.feeInSats),
                utxos: utxoInfo,
                memo: tx.memo,
                swapPayload: nil
            )
            
            self.errorMessage = ""
            return keysignPayload
            
            
            
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
            
            if tx.coin.contractAddress.isEmpty {
                
                let estimatedGas = Int64(await estimateGasForEthTransfer(tx: tx))
                
                guard estimatedGas > 0 else {
                    errorMessage = "gasEstimateETHError"
                    showAlert = true
                    isLoading = false
                    return nil
                }
                
                let keysignPayload = KeysignPayload(
                    coin: tx.coin,
                    toAddress: tx.toAddress,
                    toAmount: tx.amountInGwei, // in Gwei
                    chainSpecific: BlockChainSpecific.Ethereum(maxFeePerGasGwei: Int64(tx.gas) ?? 24, priorityFeeGwei: 1, nonce: tx.nonce, gasLimit: estimatedGas),
                    utxos: [],
                    memo: nil,
                    swapPayload: nil
                )
                
                return keysignPayload
            } else {
                
                let estimatedGas = Int64(await estimateGasForERC20Transfer(tx: tx))
                
                guard estimatedGas > 0 else {
                    errorMessage = "gasEstimateTOKENError"
                    showAlert = true
                    isLoading = false
                    return nil
                }
                
                let decimals: Double = Double(tx.token?.tokenInfo.decimals ?? "18") ?? 18
                
                let amountInSmallestUnit: Double = tx.amountDecimal * pow(10.0, decimals)
                
                let amountToSend = Int64(amountInSmallestUnit)
                
                let keysignPayload = KeysignPayload(
                    coin: tx.coin,
                    toAddress: tx.toAddress,
                    toAmount: amountToSend, // The amount must be in the token decimals
                    chainSpecific: BlockChainSpecific.ERC20(maxFeePerGasGwei: Int64(tx.gas) ?? 42, priorityFeeGwei: 1, nonce: tx.nonce, gasLimit: Int64(estimatedGas), contractAddr: tx.coin.contractAddress),
                    utxos: [],
                    memo: nil,
                    swapPayload: nil
                )
                
                return keysignPayload
            }
            
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            
            guard let accountNumberString = THORChainAccount?.accountNumber, let intAccountNumber = UInt64(accountNumberString) else {
                print("We need the ACCOUNT NUMBER to broadcast a transaction")
                return nil
            }
            
            var sequenceString = "0"
            if THORChainAccount?.sequence != nil {
                sequenceString = THORChainAccount!.sequence!
            }
            guard  let intSequence = UInt64(sequenceString) else {
                print("We need the SEQUENCE to broadcast a transaction")
                return nil
            }
            
            let keysignPayload = KeysignPayload(
                coin: tx.coin,
                toAddress: tx.toAddress,
                toAmount: tx.amountInSats,
                chainSpecific: BlockChainSpecific.THORChain(accountNumber: intAccountNumber, sequence: intSequence),
                utxos: [],
                memo: tx.memo, swapPayload: nil
            )
            
            return keysignPayload
            
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            
            guard let recentBlockHash = sol.recentBlockHash else {
                print("We need the recentBlockHash to broadcast a transaction")
                return nil
            }
            
            let keysignPayload = KeysignPayload(
                coin: tx.coin,
                toAddress: tx.toAddress,
                toAmount: tx.amountInLamports,
                chainSpecific: BlockChainSpecific.Solana(recentBlockHash: recentBlockHash),
                utxos: [],
                memo: tx.memo, swapPayload: nil
            )
            
            return keysignPayload
            
        }
        return nil
    }
}
