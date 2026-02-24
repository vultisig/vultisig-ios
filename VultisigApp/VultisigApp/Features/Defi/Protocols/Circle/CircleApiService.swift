//
//  CircleApiService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import Foundation

enum CircleApiError: Error {
    case invalidUrl
    case decodingError
    case serverError(String)
    case unauthorized
    case unknown
    case apiError(statusCode: Int, body: String?)
}

struct CircleApiService {
    static let shared = CircleApiService()

    private init() {}

    // MARK: - Public API

    struct CircleWalletItem: Decodable {
        let id: String
        let state: String?
        let walletSetId: String?
        let custodyType: String?
        let name: String?
        let address: String
        let refId: String?
        let blockchain: String?
        let accountType: String?
        let updateDate: String?
        let createDate: String?
        let scaCore: String?
    }

    func fetchWallet(ethAddress: String) async throws -> String? {
        let fetchUrlString = Endpoint.fetchCircleWallets(refId: ethAddress)
        guard let fetchUrl = URL(string: fetchUrlString) else {
            throw CircleApiError.invalidUrl
        }

        let (fetchData, fetchResponse) = try await URLSession.shared.data(from: fetchUrl)

        if let httpResponse = fetchResponse as? HTTPURLResponse {
            if (200...299).contains(httpResponse.statusCode) {
                let wallets = try JSONDecoder().decode([CircleWalletItem].self, from: fetchData)
                return wallets.first?.address
            } else {
                let body = String(data: fetchData, encoding: .utf8)
                throw CircleApiError.apiError(statusCode: httpResponse.statusCode, body: body)
            }
        }

        throw CircleApiError.unknown
    }

    func createWallet(ethAddress: String) async throws -> String {
        guard !ethAddress.isEmpty else {
            throw CircleApiError.invalidUrl
        }

        // Fetch existing wallet via refId
        if let existing = try? await fetchWallet(ethAddress: ethAddress) {
            return existing
        }

        // Create new wallet
        guard let createUrl = URL(string: Endpoint.createCircleWallet()) else {
            throw CircleApiError.invalidUrl
        }

        var request = URLRequest(url: createUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "idempotency_key": UUID().uuidString,
            "account_type": "SCA",
            "name": "Vultisig Wallet",
            "owner": ethAddress
        ]

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw CircleApiError.serverError("Failed to encode payload: \(error.localizedDescription)")
        }

        let (createData, createResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = createResponse as? HTTPURLResponse {
            if (200...299).contains(httpResponse.statusCode) {
                // Success - API returns just the address as a string
                if let addressString = String(data: createData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "") {
                    if !addressString.isEmpty {
                        return addressString
                    }
                }

                // Try as array of objects
                if let wallets = try? JSONDecoder().decode([CircleWalletItem].self, from: createData),
                   let first = wallets.first {
                    return first.address
                }

                // Try as single object
                if let wallet = try? JSONDecoder().decode(CircleWalletItem.self, from: createData) {
                    return wallet.address
                }

                throw CircleApiError.decodingError
            } else if httpResponse.statusCode == 401 {
                throw CircleApiError.unauthorized
            } else {
                let errorMsg = String(data: createData, encoding: .utf8) ?? "Unknown Error"
                throw CircleApiError.serverError("Create failed: \(httpResponse.statusCode) - \(errorMsg)")
            }
        }

        throw CircleApiError.unknown
    }
}
