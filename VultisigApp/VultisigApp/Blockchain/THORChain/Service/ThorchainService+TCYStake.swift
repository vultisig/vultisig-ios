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

    /// Parses a THORNode bank `balances` response for a single `x/staking-*`
    /// receipt denom and returns its raw (base-unit) amount.
    ///
    /// Pure so parsing is unit-testable without the LCD round-trip. Throws on a
    /// malformed response so callers can distinguish a transport/decoding failure
    /// from a genuine zero — returning `.zero` on a transient hiccup would clobber
    /// a previously good persisted position. Returns `.zero` only when the
    /// response is well-formed but carries no matching denom (genuine zero stake).
    static func parseStakingReceiptAmount(data: Data, denom: String) throws -> Decimal {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let balances = json["balances"] as? [[String: Any]] else {
            throw HelperError.runtimeError("Malformed THORNode balances response")
        }

        for balance in balances {
            if let balanceDenom = balance["denom"] as? String,
               balanceDenom == denom,
               let amountString = balance["amount"] as? String,
               let amount = UInt64(amountString) {
                return Decimal(amount)
            }
        }
        return .zero
    }

    /// Fetches the user's bank balance for a single `x/staking-*` receipt denom
    /// from THORNode. Throws on transport / decoding failure (see
    /// `parseStakingReceiptAmount`).
    private func fetchStakingReceiptAmount(address: String, denom: String) async throws -> Decimal {
        let raw = try await httpClient.request(mainnet(.balances(address: address)))
        return try Self.parseStakingReceiptAmount(data: raw.data, denom: denom)
    }

    /// Fetches the user's `x/staking-tcy` (auto-compound STCY) balance from THORNode.
    func fetchTcyAutoCompoundAmount(address: String) async throws -> Decimal {
        try await fetchStakingReceiptAmount(address: address, denom: "x/staking-tcy")
    }

    /// Fetches the user's `x/staking-x/brune` (auto-compound ybRUNE) balance from
    /// THORNode. Sibling of `fetchTcyAutoCompoundAmount`.
    func fetchBRuneAutoCompoundAmount(address: String) async throws -> Decimal {
        try await fetchStakingReceiptAmount(address: address, denom: TokensStore.ybrune.contractAddress)
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
