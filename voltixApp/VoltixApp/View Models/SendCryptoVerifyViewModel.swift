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
    
    func reloadTransactions(tx: SendTransaction, utxoBtc: BitcoinUnspentOutputsService, utxoLtc: LitecoinUnspentOutputsService, eth: EthplorerAPIService) {
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
    
    private func validateForm(tx: SendTransaction, utxoBtc: BitcoinUnspentOutputsService, utxoLtc: LitecoinUnspentOutputsService, web3Service: Web3Service) async {
        
        if !isValidForm {
            self.errorMessage = "* You must agree with the terms."
            return
        }
        
        if tx.coin.chain.name.lowercased() == Chain.Bitcoin.name.lowercased() {
            
            if let walletData = utxoBtc.walletData {
                // Calculate total amount needed by summing the amount and the fee
                let totalAmountNeeded = tx.amountInSats + tx.feeInSats
                
                // Select UTXOs sufficient to cover the total amount needed and map to UtxoInfo
                let utxoInfo = walletData.selectUTXOsForPayment(amountNeeded: Int64(totalAmountNeeded)).map {
                    UtxoInfo(
                        hash: $0.txHash ?? "",
                        amount: Int64($0.value ?? 0),
                        index: UInt32($0.txOutputN ?? -1)
                    )
                }
                
                if utxoInfo.count == 0 {
                    self.errorMessage = "You don't have enough balance to send this transaction"
                    return
                }
                
                let totalSelectedAmount = utxoInfo.reduce(0) { $0 + $1.amount }
                
                // Check if the total selected amount is greater than or equal to the needed balance
                if totalSelectedAmount < Int64(totalAmountNeeded) {
                    self.errorMessage = "You don't have enough balance to send this transaction"
                    return
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
                
                //TODO: MOVE TO NEW VIEW
//                self.presentationStack.append(.KeysignDiscovery(keysignPayload))
                
            } else {
                self.errorMessage = "Error fetching the data"
            }
            
        } else if tx.coin.chain.name.lowercased() == Chain.Litecoin.name.lowercased() {
            
            if let walletData = utxoLtc.walletData {
                let totalAmountNeeded = tx.amountInSats + tx.feeInSats
                
                let utxoInfo = walletData.selectUTXOsForPayment(amountNeeded: Int64(totalAmountNeeded)).map {
                    UtxoInfo(hash: $0.txid, amount: Int64($0.value), index: UInt32($0.vout))
                }
                
                if utxoInfo.count == 0 {
                    self.errorMessage = "You don't have enough balance to send this transaction"
                    return
                }
                
                let totalSelectedAmount = utxoInfo.reduce(0) { $0 + $1.amount }
                
                if totalSelectedAmount < Int64(totalAmountNeeded) {
                    self.errorMessage = "You don't have enough balance to send this transaction"
                    return
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
                
                //TODO: MOVE TO NEW VIEW
//                self.presentationStack.append(.KeysignDiscovery(keysignPayload))
                
                
            } else {
                self.errorMessage = "Error fetching the data"
            }
            
        } else if tx.coin.chain.name.lowercased() == Chain.Ethereum.name.lowercased() {
            
            if tx.coin.contractAddress.isEmpty {
                
                let estimatedGas = Int64(await estimateGasForEthTransfer(tx: tx, web3Service: web3Service))
                
                guard estimatedGas > 0 else {
                    errorMessage = "Error to estimate gas for ETH"
                    return
                }
                
                //TODO: MOVE TO NEW VIEW
//                self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
//                    coin: tx.coin,
//                    toAddress: tx.toAddress,
//                    toAmount: tx.amountInGwei, // in Gwei
//                    chainSpecific: BlockChainSpecific.Ethereum(maxFeePerGasGwei: Int64(tx.gas) ?? 24, priorityFeeGwei: 1, nonce: tx.nonce, gasLimit: estimatedGas),
//                    utxos: [],
//                    memo: nil,
//                    swapPayload: nil)))
            } else {
                
                let estimatedGas = Int64(await estimateGasForERC20Transfer(tx: tx, web3Service: web3Service))
                
                guard estimatedGas > 0 else {
                    errorMessage = "Error to estimate gas for the TOKEN"
                    return
                }
                
                let decimals: Double = Double(tx.token?.tokenInfo.decimals ?? "18") ?? 18
                
                let amountInSmallestUnit: Double = tx.amountDecimal * pow(10.0, decimals)
                
                let amountToSend = Int64(amountInSmallestUnit)
                
                //TODO: MOVE TO NEW VIEW
//                self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
//                    coin: tx.coin,
//                    toAddress: tx.toAddress,
//                    toAmount: amountToSend, // The amount must be in the token decimals
//                    chainSpecific: BlockChainSpecific.ERC20(maxFeePerGasGwei: Int64(tx.gas) ?? 42, priorityFeeGwei: 1, nonce: tx.nonce, gasLimit: Int64(estimatedGas), contractAddr: tx.coin.contractAddress),
//                    utxos: [],
//                    memo: nil,
//                    swapPayload: nil)))
            }
            
        } else if tx.coin.chain.name.lowercased() == Chain.THORChain.name.lowercased() {
            
            guard let accountNumberString = thor.account?.accountNumber, let intAccountNumber = UInt64(accountNumberString) else {
                print("We need the ACCOUNT NUMBER to broadcast a transaction")
                return
            }
            
            guard let sequenceString = thor.account?.sequence, let intSequence = UInt64(sequenceString) else {
                print("We need the SEQUENCE to broadcast a transaction")
                return
            }
            
            //TODO: MOVE TO NEW VIEW
//            self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
//                coin: tx.coin,
//                toAddress: tx.toAddress,
//                toAmount: tx.amountInSats,
//                chainSpecific: BlockChainSpecific.THORChain(accountNumber: intAccountNumber, sequence: intSequence),
//                utxos: [],
//                memo: tx.memo, swapPayload: nil)))
            
        } else if tx.coin.chain.name.lowercased() == Chain.Solana.name.lowercased() {
            
            guard let recentBlockHash = sol.recentBlockHash else {
                print("We need the recentBlockHash to broadcast a transaction")
                return
            }
            
            //TODO: MOVE TO NEW VIEW
//            self.presentationStack.append(.KeysignDiscovery(KeysignPayload(
//                coin: tx.coin,
//                toAddress: tx.toAddress,
//                toAmount: tx.amountInLamports,
//                chainSpecific: BlockChainSpecific.Solana(recentBlockHash: recentBlockHash),
//                utxos: [],
//                memo: tx.memo, swapPayload: nil)))
            
        }
    }
}
