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

        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, _, error in
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
                   let amount = UInt64(amountString) {
                    completion(Decimal(amount))
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
               let amount = UInt64(amountString) {
                return Decimal(amount)
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
            logger.debug("Failed to fetch merge accounts: \(error.localizedDescription)")
            return []
        }
    }

    func fetchTcyAutoCompoundAmount(address: String) async -> Decimal {
        // Use THORNode endpoint to get all balances and find x/staking-tcy
        let allBalancesUrl = Endpoint.fetchAccountBalanceThorchainNineRealms(address: address)

        guard let url = URL(string: allBalancesUrl) else {
            return .zero
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let balances = json["balances"] as? [[String: Any]] {

                for balance in balances {
                    if let denom = balance["denom"] as? String,
                       denom == "x/staking-tcy",
                       let amountString = balance["amount"] as? String,
                       let amount = UInt64(amountString) {
                        return Decimal(amount)
                    }
                }
            }
        } catch {
            print("Error fetching auto-compound balance: \(error.localizedDescription)")
        }

        return .zero
    }

    func fetchTcyAutoCompoundStatus() async -> (sharePrice: Decimal, totalShares: Decimal) {
        let urlString = Endpoint.fetchTcyAutoCompoundStatus()
        guard let url = URL(string: urlString) else {
            return (.zero, .zero)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataBase64 = json["data"] as? String,
               let decoded = Data(base64Encoded: dataBase64),
               let status = try JSONSerialization.jsonObject(with: decoded) as? [String: Any],
               let liquidBondSizeStr = status["liquid_bond_size"] as? String,
               let liquidBondSharesStr = status["liquid_bond_shares"] as? String,
               let liquidBondSize = UInt64(liquidBondSizeStr),
               let liquidBondShares = UInt64(liquidBondSharesStr) {

                let sizeDecimal = Decimal(liquidBondSize)
                let sharesDecimal = Decimal(liquidBondShares)
                let sharePrice = sharesDecimal > 0 ? sizeDecimal / sharesDecimal : .zero

                return (sharePrice, sharesDecimal)
            } else {
                return (.zero, .zero)
            }
        } catch {
            print("Error fetching auto-compound status: \(error.localizedDescription)")
            return (.zero, .zero)
        }
    }

}
