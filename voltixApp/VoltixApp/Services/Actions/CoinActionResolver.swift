//
//  ChainActionResolver.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 01.05.2024.
//

import Foundation

struct CoinActionResolver {

    let json = """
    {
        "disabled": {
            "solana": ["swap", "bond"]
        }
    }
    """

    func resolveActions(for chain: Chain) async -> [CoinAction] {
        let jsonData = Data(json.utf8)
        
        guard let config = try? JSONDecoder().decode(Config.self, from: jsonData) else {
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
}
