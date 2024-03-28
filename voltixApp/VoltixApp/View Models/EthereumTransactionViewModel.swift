//
//  EthereumTransactionViewModel.swift
//  VoltixApp
//
//  Created by Johnny Luo on 28/3/2024.
//

import Foundation

@MainActor
class EthereumTransactionViewModel : ObservableObject{
    var chain: Chain?
    var vault: Vault = Vault(name: "temp")
    
    @Published var transactions: [EtherscanAPITransactionDetail] = []
    @Published var contractAddress: String?
    @Published var addressFor: String = ""
    var etherScanService: EtherScanService = .shared
    
    func setData(chain:Chain?,vault:Vault) async {
        self.chain = chain
        self.vault = vault
        switch chain?.name {
        case Chain.Ethereum.name:
            await loadETHTransactions(vault: vault)
        case Chain.BSCChain.name:
            await loadBSCTransactions(vault: vault)
        default:
            return
        }
    }
    
    func loadBSCTransactions(vault: Vault) async {
        let bnb = vault.coins.first{$0.ticker == "BNB"}
        guard let bnb else {
            return
        }
        do {
            var transactions: [EtherscanAPITransactionDetail] = []
            var forAddress: String = ""
            if let contract = contractAddress {
                (transactions, forAddress) = try await BSCService.shared.fetchBEP20Transactions(
                    forAddress: bnb.address,
                    contractAddress: contract
                )
            } else {
                (transactions, forAddress) = try await BSCService.shared.fetchTransactions(forAddress: bnb.address)
            }
            addressFor = forAddress
            self.transactions = transactions
        } catch {
            print("error: \(error)")
        }
    }
    func loadETHTransactions(vault:Vault) async{
        let eth = vault.coins.first{$0.ticker == "ETH"}
        guard let eth else {
            return
        }
        do {
            var transactions: [EtherscanAPITransactionDetail] = []
            var forAddress: String = ""
            if let contract = contractAddress {
                (transactions, forAddress) = try await etherScanService.fetchERC20Transactions(
                    forAddress: eth.address,
                    contractAddress: contract
                )
            } else {
                (transactions, forAddress) = try await etherScanService.fetchTransactions(forAddress: eth.address)
            }
            addressFor = forAddress
            self.transactions = transactions
        } catch {
            print("error: \(error)")
        }
    }
}
