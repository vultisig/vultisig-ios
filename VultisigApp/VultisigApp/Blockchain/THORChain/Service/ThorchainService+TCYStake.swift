//
//  ThorchainService+TCYStake.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

extension ThorchainService {

    func fetchTcyStakedAmount(address: String) async -> Decimal {
        do {
            let raw = try await httpClient.request(mainnet(.tcyStaker(address: address)))
            guard let json = try JSONSerialization.jsonObject(with: raw.data) as? [String: Any],
                  let amountString = json["amount"] as? String,
                  let amount = UInt64(amountString) else {
                return .zero
            }
            return Decimal(amount)
        } catch {
            print("Error fetching or decoding staked amount: \(error.localizedDescription)")
            return .zero
        }
    }

    func fetchMergeAccounts(address: String) async -> [MergeAccountResponse.ResponseData.Node.AccountMerge.MergeAccount] {
        let id = "Account:\(address)".data(using: .utf8)?.base64EncodedString() ?? ""

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

        do {
            let response = try await httpClient.request(
                mainnet(.rujiGraphQL(query: query)),
                responseType: MergeAccountResponse.self
            )
            return response.data.data.node?.merge?.accounts ?? []
        } catch {
            logger.debug("Failed to fetch merge accounts: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches the user's `x/staking-tcy` (auto-compound STCY) balance from THORNode.
    ///
    /// Throws on transport / decoding failure — callers MUST distinguish this from a
    /// successful zero. Silently swallowing the error and returning `.zero` (the previous
    /// behavior) caused persisted STCY positions to be overwritten with zero on every
    /// transient hiccup.
    ///
    /// Returns `.zero` only when the endpoint responds successfully but the user has no
    /// `x/staking-tcy` balance in the response (genuine zero stake).
    func fetchTcyAutoCompoundAmount(address: String) async throws -> Decimal {
        let raw = try await httpClient.request(mainnet(.balances(address: address)))
        guard let json = try JSONSerialization.jsonObject(with: raw.data) as? [String: Any],
              let balances = json["balances"] as? [[String: Any]] else {
            throw HelperError.runtimeError("Malformed THORNode balances response")
        }

        for balance in balances {
            if let denom = balance["denom"] as? String,
               denom == "x/staking-tcy",
               let amountString = balance["amount"] as? String,
               let amount = UInt64(amountString) {
                return Decimal(amount)
            }
        }
        return .zero
    }

    func fetchTcyAutoCompoundStatus() async -> (sharePrice: Decimal, totalShares: Decimal) {
        do {
            let raw = try await httpClient.request(mainnet(.tcyAutoCompoundStatus))
            guard let json = try JSONSerialization.jsonObject(with: raw.data) as? [String: Any],
                  let dataBase64 = json["data"] as? String,
                  let decoded = Data(base64Encoded: dataBase64),
                  let status = try JSONSerialization.jsonObject(with: decoded) as? [String: Any],
                  let liquidBondSizeStr = status["liquid_bond_size"] as? String,
                  let liquidBondSharesStr = status["liquid_bond_shares"] as? String,
                  let liquidBondSize = UInt64(liquidBondSizeStr),
                  let liquidBondShares = UInt64(liquidBondSharesStr) else {
                return (.zero, .zero)
            }

            let sizeDecimal = Decimal(liquidBondSize)
            let sharesDecimal = Decimal(liquidBondShares)
            let sharePrice = sharesDecimal > 0 ? sizeDecimal / sharesDecimal : .zero

            return (sharePrice, sharesDecimal)
        } catch {
            print("Error fetching auto-compound status: \(error.localizedDescription)")
            return (.zero, .zero)
        }
    }

}
