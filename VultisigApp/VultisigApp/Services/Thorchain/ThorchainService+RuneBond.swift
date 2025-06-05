//
//  ThorchainService+RuneBond.swift
//  VultisigApp
//
//  Created on 05/06/2025.
//

import Foundation

extension ThorchainService {
    
    // MARK: - Public Methods
    
    /// Fetches the total bonded RUNE amount for a given address using completion handler
    func fetchRuneBondedAmount(address: String, completion: @escaping (Decimal) -> Void) {
        let urlString = Endpoint.fetchRuneBondedAmount(address: address)
        guard let url = URL(string: urlString) else {
            completion(.zero)
            return
        }
        
        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, _, error in
            guard let data = data, error == nil else {
                completion(.zero)
                return
            }
            completion(self.parseRuneBondedAmount(from: data))
        }
        
        task.resume()
    }
    
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
        
        return totalBond
    }
}
