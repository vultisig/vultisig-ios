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
    
    func fetchTcyStakedAmount(address: String) async -> Decimal {
        let urlString = Endpoint.fetchTcyStakedAmount(address: address)
        guard let url = URL(string: urlString) else {
            return .zero
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let amountString = json["amount"] as? String,
               let stakedAmountInt = UInt64(amountString) {
                return Decimal(stakedAmountInt) / Decimal(100_000_000)
            } else {
                return .zero
            }
        } catch {
            print("Error fetching or decoding staked amount: \(error.localizedDescription)")
            return .zero
        }
    }
    
    func fetchMergeAccounts(address: String) async -> [MergeAccountResponse.ResponseData.Node.AccountMerge.MergeAccount] {
        let id = "Account:\(address)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        guard let url = URL(string: Endpoint.fetchThorchainMergedAssets()) else {
            print("Invalid GraphQL URL")
            return []
        }

        let query = """
        {
          node(id: "\(id)") {
            ... on Account {
              merge {
                accounts {
                  pool {
                    mergeAsset {
                      metadata {
                        symbol
                      }
                    }
                  }
                  size {
                    amount
                  }
                  shares
                }
              }
            }
          }
        }
        """

        let requestBody: [String: Any] = ["query": query]

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData

            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(MergeAccountResponse.self, from: data)

            return decoded.data.node?.merge?.accounts ?? []
        } catch {
            print("Failed to fetch merge accounts: \(error)")
            return []
        }
    }
    
    func fetchNodeBonds(address: String, completion: @escaping ([ThorchainActiveNodeBondResponse]) -> Void) {
        //let urlString = "https://midgard.ninerealms.com/v2/bonds/\(address)"
        
        let urlString = "https://midgard.ninerealms.com/v2/bonds/thor1fpyaj39rdlc5f80kulq55tqlvku4t66gq5pvqk"
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }

        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, response, error in
            if let error = error {
                print("Error fetching node bonds: \(error)")
                completion([])
                return
            }

            guard let data = data else {
                completion([])
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let nodes = json["nodes"] as? [[String: Any]] {

                    var result: [ThorchainActiveNodeBondResponse] = []

                    for node in nodes {
                        if let nodeAddress = node["address"] as? String,
                           let bondStr = node["bond"] as? String,
                           let bond = UInt64(bondStr),
                           let status = node["status"] as? String {

                            let bondDecimal = Decimal(bond) / Decimal(100_000_000)
                            result.append(ThorchainActiveNodeBondResponse(nodeAddress: nodeAddress, bondAmount: bondDecimal, status: status))
                        }
                    }

                    completion(result)
                } else {
                    completion([])
                }
            } catch {
                print("Error decoding JSON: \(error.localizedDescription)")
                completion([])
            }
        }

        task.resume()
    }
    
}
