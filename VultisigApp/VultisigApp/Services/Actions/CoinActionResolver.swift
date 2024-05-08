//
//  ChainActionResolver.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

final class CoinActionResolver {

    private var config: Config?

    init() {
        Task {
            _ = try? await fetchConfig()
        }
    }

    func resolveActions(for chain: Chain) async -> [CoinAction] {

        guard let config = try? await getConfig(for: chain) else {
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

    private func getConfig(for chain: Chain) async throws -> Config {
        if let config {
            return config
        }
        return try await fetchConfig()
    }

    private func fetchConfig() async throws -> Config {
        let url = URL(string: "https://api.voltix.org/actions/default.json")!

        let (_, _) = try await URLSession.shared.data(from: url)

        let jsonData = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(Config.self, from: jsonData)
        self.config = config
        return config
    }
}
