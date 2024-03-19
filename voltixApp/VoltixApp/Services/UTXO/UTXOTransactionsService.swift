import SwiftUI

enum UTXOTransactionError: Error {
	case invalidURL
	case httpError(Int) // Includes the HTTP status code
	case apiError(String) // Error message from the API
	case unexpectedResponse
	case unknown(Error) // Wraps an unknown error
}

@MainActor
public class UTXOTransactionsService: ObservableObject {
	@Published var walletData: [UTXOTransactionMempool]?
	@Published var errorMessage: String?
	
	// Cache structure to hold data and timestamp
	private struct CacheEntry {
		let data: [UTXOTransactionMempool]
		let timestamp: Date
	}
	
	// Dictionary to store cache entries with userAddress as the key
	private var cache: [String: CacheEntry] = [:]
	
	// Function to check if cache for a given userAddress is valid (not older than 5 minutes)
	private func isCacheValid(for userAddress: String) -> Bool {
		if let entry = cache[userAddress], -entry.timestamp.timeIntervalSinceNow < 300 {
			return true // Cache is valid if less than 5 minutes old
		}
		return false
	}
	
	func fetchTransactions(_ userAddress: String, endpointUrl: String) async {
			// Use cache if it's valid for the requested userAddress
		if isCacheValid(for: userAddress), let cachedData = cache[userAddress]?.data {
			self.walletData = cachedData
			return
		}
		
		guard let url = URL(string: endpointUrl) else {
			errorMessage = "Invalid URL"
			return
		}
		
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
				// print(String(data: data, encoding: .utf8) ?? "No response body")
			let decoder = JSONDecoder()
			let decodedData = try decoder.decode([UTXOTransactionMempool].self, from: data)
			let updatedData = decodedData.map { transaction in
				UTXOTransactionMempool(txid: transaction.txid, version: transaction.version, locktime: transaction.locktime, vin: transaction.vin, vout: transaction.vout, fee: transaction.fee, status: transaction.status, userAddress: userAddress)
			}
			
			cache[userAddress] = CacheEntry(data: updatedData, timestamp: Date())
			self.walletData = updatedData
		} catch let DecodingError.dataCorrupted(context) {
			errorMessage = "Data corrupted: \(context)"
		} catch let DecodingError.keyNotFound(key, context) {
			errorMessage = "Key '\(key)' not found: \(context.debugDescription)"
		} catch let DecodingError.valueNotFound(value, context) {
			errorMessage = "Value '\(value)' not found: \(context.debugDescription)"
		} catch let DecodingError.typeMismatch(type, context) {
			errorMessage = "Type '\(type)' mismatch: \(context.debugDescription)"
		} catch {
			errorMessage = "Error: \(error.localizedDescription)"
		}
		
		print(String(describing: errorMessage))
	}
	
	public static func broadcastTransaction(chain: String, signedTransaction: String, completion: @escaping (Result<String, Error>) -> Void) {
		
		guard let url = URL(string: Endpoint.blockchairBroadcast(chain.lowercased())) else {
			completion(.failure(NSError(domain: "BlockchairServiceError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
			return
		}
		
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.addValue("application/json", forHTTPHeaderField: "Content-Type")
		
		let postData: [String: Any] = ["data": signedTransaction]
		guard let httpBody = try? JSONSerialization.data(withJSONObject: postData, options: []) else {
			completion(.failure(NSError(domain: "BlockchairServiceError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize data"])))
			return
		}
		request.httpBody = httpBody
		
		let task = URLSession.shared.dataTask(with: request) { data, response, error in
			if let error = error {
				completion(.failure(error))
				return
			}
			
			guard let httpResponse = response as? HTTPURLResponse else {
				completion(.failure(NSError(domain: "BlockchairServiceError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response received"])))
				return
			}
			
			if httpResponse.statusCode == 200, let jsonData = data {
				do {
					if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
					   let transactionData = json["data"] as? [String: Any],
					   let transactionHash = transactionData["transaction_hash"] as? String {
						DispatchQueue.main.async {
							completion(.success(transactionHash))
						}
					} else {
						completion(.failure(NSError(domain: "BlockchairServiceError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])))
					}
				} catch {
					completion(.failure(error))
				}
			} else if httpResponse.statusCode == 400, let jsonData = data {
				do {
					if let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
					   let context = json["context"] as? [String: Any],
					   let errorDescription = context["error"] as? String {
						DispatchQueue.main.async {
							completion(.failure(NSError(domain: "BlockchairServiceError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to broadcast transaction. Error: \(errorDescription)"])))
						}
					}
				} catch {
					completion(.failure(error))
				}
			} else {
				completion(.failure(NSError(domain: "BlockchairServiceError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Received HTTP \(httpResponse.statusCode)"])))
			}
		}
		
		task.resume()
	}
}
