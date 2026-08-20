//
//  DoneTransactionPresentation.swift
//  VultisigApp
//

import Foundation

/// Adapts the shared signed-transaction reading to Done's completed-action
/// vocabulary. It owns no chain parsing and no amount formatting.
enum DoneTransactionPresentation {

    /// These readings intentionally retain the normal-send card's `Sent`
    /// fallback and its already-computed amount. A generic contract call or an
    /// unreadable transaction does not justify replacing that richer fallback.
    private static let fallbackOperations: Set<DecodedOperation> = [
        .transfer, .contractCall, .unknown
    ]

    static func specificTitle(for payload: KeysignPayload) -> String? {
        let operation = SignedTransactionDecoder.decode(payload).operation
        guard !fallbackOperations.contains(operation) else { return nil }
        return DecodedTransactionPresentation.doneTitle(for: operation)
    }

    static func hero(
        for payload: KeysignPayload,
        trustedCoins: [Coin]
    ) -> HeroContent? {
        let decoded = SignedTransactionDecoder.decode(payload)
        guard !fallbackOperations.contains(decoded.operation),
              let title = DecodedTransactionPresentation.doneTitle(for: decoded.operation)
        else { return nil }

        return DecodedTransactionPresentation.hero(
            for: decoded,
            coin: trustedCoin(for: payload, in: trustedCoins),
            title: title
        )
    }

    static func resolve(
        for payload: KeysignPayload,
        trustedCoins: [Coin],
        readers: [PositionReading] = ResolvedTransactionHero.readers
    ) async -> HeroContent? {
        let decoded = SignedTransactionDecoder.decode(payload)
        guard !fallbackOperations.contains(decoded.operation),
              let title = DecodedTransactionPresentation.doneTitle(for: decoded.operation)
        else { return nil }

        if let projected = await ResolvedTransactionHero.resolve(
            for: payload,
            trustedCoins: trustedCoins,
            title: title,
            readers: readers
        ) {
            return projected
        }

        return DecodedTransactionPresentation.hero(
            for: decoded,
            coin: trustedCoin(for: payload, in: trustedCoins),
            title: title
        )
    }

    static func retitleResolvedHero(
        _ hero: HeroContent?,
        for payload: KeysignPayload
    ) -> HeroContent? {
        hero?.retitled(specificTitle(for: payload))
    }

    private static func trustedCoin(for payload: KeysignPayload, in coins: [Coin]) -> Coin {
        coins.first {
            $0.chain == payload.coin.chain &&
                $0.ticker.caseInsensitiveCompare(payload.coin.ticker) == .orderedSame &&
                $0.contractAddress.caseInsensitiveCompare(payload.coin.contractAddress) == .orderedSame
        } ?? payload.coin
    }
}
