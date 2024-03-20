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
    private init() {}
	
    @Published var blockchairData: [String: Blockchair] = [:]
    @Published var errorMessage: [String: String] = [:]
	
    public func fetchBlockchairData(for address: String, coinName: String) async {
        let coinName = coinName.lowercased()
        let key = "\(address)-\(coinName)"
		
        guard let url = URL(string: Endpoint.blockchairDashboard(address, coinName)) else {
            print("Invalid URL")
            return
        }
		
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // print(String(data: data, encoding: .utf8))
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decodedData = try decoder.decode(BlockchairResponse.self, from: data)
            if let blockchairData = decodedData.data[address] {
                self.blockchairData[key] = blockchairData
            }
        } catch let error as DecodingError {
            self.errorMessage[key] = Utils.handleJsonDecodingError(error)
        } catch {
            print("Error: \(error.localizedDescription)")
            self.errorMessage[key] = "Error: \(error.localizedDescription)"
        }
    }
}
