//
//  ThorchainService+RuneBond.swift
//  VultisigApp
//
//  Created on 05/06/2025.
//

import Foundation

private let runeBondBaseUnit: Decimal = 100_000_000 // RUNE uses 8 decimals (1e8 base units)

extension ThorchainService {
    
    // MARK: - Public Methods
    
    /// Fetches the total bonded RUNE amount for a given address using completion handler
    /// - Parameters:
    ///   - address: The THORChain address to check for bonded RUNE
    ///   - completion: Completion handler with the total bonded amount in RUNE (not base units)
    func fetchRuneBondedAmount(address: String, completion: @escaping (Decimal) -> Void) {
        let urlString = Endpoint.fetchRuneBondedAmount(address: address)
        guard let url = URL(string: urlString) else {
            completion(.zero)
            return
        }
        
        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                completion(.zero)
                return
            }
            completion(self.parseRuneBondedAmount(from: data))
        }
        
        task.resume()
    }
    
    /// Fetches the total bonded RUNE amount for a given address using async/await
    /// - Parameter address: The THORChain address to check for bonded RUNE
    /// - Returns: The total bonded amount in RUNE (not base units)
    func fetchRuneBondedAmount(address: String) async -> Decimal {
        let urlString = Endpoint.fetchRuneBondedAmount(address: address)
        guard let url = URL(string: urlString) else { return .zero }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parseRuneBondedAmount(from: data)
        } catch {
            print("Error fetching bonded amount: \(error.localizedDescription)")
            return .zero
        }
    }
    
    // MARK: - Private Helpers
    
    /// Parses the response data and calculates the total bonded RUNE amount
    /// - Parameter data: The data received from the API
    /// - Returns: The total bonded amount in RUNE (not base units)
    private func parseRuneBondedAmount(from data: Data) -> Decimal {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = json["nodes"] as? [[String: Any]] else {
            return .zero
        }
        
        var totalBond: Decimal = 0
        for node in nodes {
            if let bondStr = node["bond"] as? String,
               let bondInt = UInt64(bondStr) {
                totalBond += Decimal(bondInt)
            }
        }
        
        // Convert from base units to RUNE (1 RUNE = 1e8 base units)
        return totalBond / runeBondBaseUnit
    }
}

// MARK: - Endpoint Extension

extension Endpoint {
    /// Creates the URL for fetching bonded RUNE amounts for a given address
    /// - Parameter address: The THORChain address
    /// - Returns: The full URL string for the API endpoint
    static func fetchRuneBondedAmount(address: String) -> String {
        return "https://midgard.ninerealms.com/v2/bonds/\(address)"
    }
}
