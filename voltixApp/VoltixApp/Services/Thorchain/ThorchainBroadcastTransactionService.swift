    //
    //  ThorchainBroadcastTransactionService.swift
    //  VoltixApp
    //
    //  Created by Enrique Souza Soares on 07/03/2024.
    //

import Foundation

extension ThorchainService {
    
    func broadcastTransaction(jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "https://thornode.ninerealms.com/cosmos/tx/v1beta1/txs")!
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            completion(.failure(NSError(domain: "ThorchainService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to Data"])))
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
            
            // print(String(data: data, encoding: String.Encoding.utf8))
            
            if (200...299).contains(httpResponse.statusCode) {
                do {
                    let response = try JSONDecoder().decode(ThorchainTransactionBroadcastResponse.self, from: data)
                    
                        // Check if the transaction was successful based on the `code` field
                    if let code = response.txResponse?.code, code == 0 {
                            // Transaction successful
                        if let txHash = response.txResponse?.txhash {
                            completion(.success(txHash))
                        } else {
                            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transaction hash not available."])))
                        }
                    } else {
                            // Transaction failed - use the rawLog as the error message if available
                        let rawLog = response.txResponse?.rawLog ?? "Unknown error"
                        completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: rawLog])))
                    }
                    
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
