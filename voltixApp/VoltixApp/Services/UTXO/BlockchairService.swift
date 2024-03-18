	//
	//  BlockchairService.swift
	//  VoltixApp
	//
	//  Created by Enrique Souza Soares on 17/03/2024.
	//

import Foundation

@MainActor
public class BlockchairService: ObservableObject {
	
	static let shared = BlockchairService()
	private init(){}
	
	@Published var blockchairData: [String: Blockchair]?
	@Published var errorMessage: [String: String]?
	
	public func fetchBlockchairData(for address: String, coinName: String) async {
		
		let coinName = coinName.lowercased().replacingOccurrences(of: Chain.BitcoinCash.name.lowercased(), with: "bitcoin-cash")
		
		let key: String = "\(address)-\(coinName)"
		
		guard let url = URL(string: Endpoint.blockchairDashboard(address, coinName)) else {
			print("Invalid URL")
			return
		}
		
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			
			print(String(data: data, encoding: .utf8))
			let decoder = JSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			let decodedData = try decoder.decode(BlockchairResponse.self, from: data)
			if let blockchairData = decodedData.data[address] {
				if self.blockchairData == nil {
					self.blockchairData = [String: Blockchair]()
				}
				self.blockchairData?[key] = blockchairData
			}
		} catch let DecodingError.dataCorrupted(context) {
			print("Data corrupted: \(context)")
			self.errorMessage = self.errorMessage ?? [String: String]()
			self.errorMessage?[key] = "Data corrupted: \(context)"
		} catch let DecodingError.keyNotFound(key2, context) {
			print("Key '\(key)' not found: \(context.debugDescription)")
			self.errorMessage = self.errorMessage ?? [String: String]()
			self.errorMessage?[key] = "Key '\(key2)' not found: \(context.debugDescription)"
		} catch let DecodingError.valueNotFound(value, context) {
			print("Value '\(value)' not found: \(context.debugDescription)")
			self.errorMessage = self.errorMessage ?? [String: String]()
			self.errorMessage?[key] = "Value '\(value)' not found: \(context.debugDescription)"
		} catch let DecodingError.typeMismatch(type, context) {
			print("Type '\(type)' mismatch: \(context.debugDescription)")
			self.errorMessage = self.errorMessage ?? [String: String]()
			self.errorMessage?[key] = "Type '\(type)' mismatch: \(context.debugDescription)"
		} catch {
			print("Error: \(error.localizedDescription)")
			self.errorMessage = self.errorMessage ?? [String: String]()
			self.errorMessage?[key] = "Error: \(error.localizedDescription)"
		}
	}
	
}

