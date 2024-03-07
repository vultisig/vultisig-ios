    //
    //  ThorchainBroadcastTransactionService.swift
    //  VoltixApp
    //
    //  Created by Enrique Souza Soares on 07/03/2024.
    //

import Foundation



extension ThorchainService {
    
    enum BroadcastMode: String {
        case block = "BROADCAST_MODE_BLOCK"
        case sync = "BROADCAST_MODE_SYNC"
        case async = "BROADCAST_MODE_ASYNC"
    }
    
    func broadcastTransaction(signedTx: String, mode: BroadcastMode, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "https://thornode.ninerealms.com/cosmos/tx/v1beta1/txs")!
        
            // Use the BroadcastMode enum for setting the mode in the requestBody
        let requestBody = ["tx_bytes": signedTx, "mode": mode.rawValue]
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            completion(.failure(NSError(domain: "ThorchainService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request body"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "ThorchainService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data or response"])))
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                do {
                    let response = try JSONDecoder().decode(TransactionBroadcastResponse.self, from: data)
                    completion(.success(response.txHash))
                } catch {
                    completion(.failure(error))
                }
            } else {
                do {
                    let errorResponse = try JSONDecoder().decode(ThorchainErrorResponse.self, from: data)
                    let errorMessage = "\(errorResponse.message) (Code: \(errorResponse.code))"
                    completion(.failure(NSError(domain: "ThorchainService", code: errorResponse.code, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                } catch {
                    completion(.failure(NSError(domain: "ThorchainService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode error response"])))
                }
            }
        }
        task.resume()
    }
}

