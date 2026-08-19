//
//  ResolvedTransactionHero.swift
//  VultisigApp
//

import Foundation

/// Resolves an execution-set amount from chain state.
protocol PositionReading {
    func handles(_ decoded: DecodedTransaction, coin: Coin) -> Bool
    func amount(for decoded: DecodedTransaction, coin: Coin) async -> HeroCoinAmount?
}

enum ResolvedTransactionHero {
    /// Chain PRs add readers here as their signed decoders become available.
    static let readers: [PositionReading] = []

    static func resolve(
        for content: SignedTransactionContent,
        trustedCoins: [Coin],
        readers: [PositionReading] = ResolvedTransactionHero.readers
    ) async -> HeroContent? {
        let decoded = SignedTransactionDecoder.decode(content)
        guard let title = DecodedTransactionPresentation.title(for: decoded.operation) else { return nil }

        for reader in readers {
            guard let coin = trustedCoins.first(where: { reader.handles(decoded, coin: $0) }) else {
                continue
            }
            let amount = await ProjectionCoordinator.estimate {
                await reader.amount(for: decoded, coin: coin)
            }
            return ProjectionCoordinator.hero(for: decoded, title: title, estimate: amount)
        }
        return nil
    }
}
