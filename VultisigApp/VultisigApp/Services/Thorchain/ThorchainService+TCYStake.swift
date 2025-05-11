//
//  ThorchainService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

extension ThorchainService {

    func fetchTcyStakedAmount(address: String, completion: @escaping (Decimal) -> Void) {
        let urlString = Endpoint.fetchTcyStakedAmount(address: address)
        guard let url = URL(string: urlString) else {
            completion(.zero)
            return
        }

        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, response, error in
            if let error = error {
                print("Error to fetch staked amount: \(error)")
                completion(.zero)
                return
            }

            guard let data = data else {
                completion(.zero)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let amountString = json["amount"] as? String,
                   let stakedAmountInt = UInt64(amountString) {
                    let stakedAmountDecimal = Decimal(stakedAmountInt) / Decimal(100_000_000)
                    completion(stakedAmountDecimal)
                } else {
                    completion(.zero)
                }
            } catch {
                print("Error to decode staked amount: \(error.localizedDescription)")
                completion(.zero)
            }
        }

        task.resume()
    }
}
