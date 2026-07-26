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
    case unauthorized
    case notFound
    case apiError(statusCode: Int, body: String?)
}

struct CircleApiService {
    static let shared = CircleApiService()

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

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
        do {
            let response = try await httpClient.request(
                CircleAPI.getWallet(refId: ethAddress),
                responseType: [CircleWalletItem].self
            )
            return response.data.first?.address
        } catch HTTPError.statusCode(let code, let data) {
            // Distinguish "wallet missing" (404) from outages so callers don't
            // POST a duplicate wallet on a 5xx/proxy failure.
            if code == 404 {
                throw CircleApiError.notFound
            }
            let body = data.flatMap { String(data: $0, encoding: .utf8) }
            throw CircleApiError.apiError(statusCode: code, body: body)
        }
    }

    func createWallet(ethAddress: String) async throws -> String {
        guard !ethAddress.isEmpty else {
            throw CircleApiError.invalidUrl
        }

        do {
            if let existing = try await fetchWallet(ethAddress: ethAddress) {
                return existing
            }
        } catch CircleApiError.notFound {
            // Fall through to POST a new wallet.
        }

        let payload = CircleCreateWalletRequest(
            idempotencyKey: UUID().uuidString,
            accountType: "SCA",
            name: "Vultisig Wallet",
            owner: ethAddress
        )

        let response = try await httpClient.request(CircleAPI.createWallet(request: payload))

        if response.response.statusCode == 401 {
            throw CircleApiError.unauthorized
        }

        // The Circle proxy is inconsistent: it sometimes returns a bare
        // quoted address string, sometimes a single wallet object, and
        // sometimes a single-item array. Try each shape in turn.
        if let addressString = String(data: response.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: ""),
           !addressString.isEmpty,
           !addressString.hasPrefix("{"),
           !addressString.hasPrefix("[") {
            return addressString
        }

        if let wallets = try? JSONDecoder().decode([CircleWalletItem].self, from: response.data),
           let first = wallets.first {
            return first.address
        }

        if let wallet = try? JSONDecoder().decode(CircleWalletItem.self, from: response.data) {
            return wallet.address
        }

        throw CircleApiError.decodingError
    }
}
