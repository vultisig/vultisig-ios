//
//  ChainActionResolver.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

enum CoinActionsAPI: TargetType {
    case getDefault

    var baseURL: URL { URL(string: "https://api.vultisig.com")! }
    var path: String { "/actions/default.json" }
    var method: HTTPMethod { .get }
    var task: HTTPTask { .requestPlain }
}

final class CoinActionResolver {

    private var config: Config?
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
        Task {
            _ = try? await fetchConfig()
        }
    }

    func resolveActions(for chain: Chain) async -> [CoinAction] {
        guard let config = try? await getConfig() else {
            return chain.defaultActions
        }
        guard let disabled = config.disabled[chain.rawValue] else {
            return chain.defaultActions
        }

        return chain.defaultActions.filter { !disabled.contains($0) }
    }
}

private extension CoinActionResolver {

    struct Config: Codable {
        let disabled: [String: [CoinAction]]
    }

    private func getConfig() async throws -> Config {
        if let config {
            return config
        }
        return try await fetchConfig()
    }

    private func fetchConfig() async throws -> Config {
        let response = try await httpClient.request(CoinActionsAPI.getDefault, responseType: Config.self)
        self.config = response.data
        return response.data
    }
}
