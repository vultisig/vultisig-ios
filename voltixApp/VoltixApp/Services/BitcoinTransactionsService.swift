//
//  UnspentOutputsViewModel.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 13/02/2024.
//
import SwiftUI

@MainActor
public class BitcoinTransactionsService: ObservableObject {
    @Published var walletData: [BitcoinTransactionMempool]?
    @Published var errorMessage: String?
    
    func fetchTransactions(_ userAddress: String) async {
        
        print("https://mempool.space/api/address/\(userAddress)/txs")
        
        guard let url = URL(string: "https://mempool.space/api/address/\(userAddress)/txs") else {
            errorMessage = "Invalid URL"
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode([BitcoinTransactionMempool].self, from: data)
            
            self.walletData = decodedData.map { transaction in
                BitcoinTransactionMempool(txid: transaction.txid, version: transaction.version, locktime: transaction.locktime, vin: transaction.vin, vout: transaction.vout, fee: transaction.fee, status: transaction.status, userAddress: userAddress)
            }
        } catch let DecodingError.dataCorrupted(context) {
            print(context)
        } catch let DecodingError.keyNotFound(key, context) {
            print("Key '\(key)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
        } catch let DecodingError.valueNotFound(value, context) {
            print("Value '\(value)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
        } catch let DecodingError.typeMismatch(type, context)  {
            print("Type '\(type)' mismatch:", context.debugDescription)
            print("codingPath:", context.codingPath)
        } catch {
            print("error: ", error)
        }
    }
}
