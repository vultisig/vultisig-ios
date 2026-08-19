//
//  ResolvedTransactionHero.swift
//  VultisigApp
//
//  Resolves optional chain-state amounts behind decoder-layer readers, keeping
//  chain knowledge out of keysign view models.
//

import Foundation

/// Resolves an execution-set amount from chain state.
protocol PositionReading {
    /// Whether this reader answers for the decoded transaction on this coin.
    func handles(_ decoded: DecodedTransaction, coin: Coin) -> Bool

    /// The resolved amount, or `nil` when the read failed or returned nothing.
    func amount(for decoded: DecodedTransaction, coin: Coin) async -> HeroCoinAmount?
}

enum ResolvedTransactionHero {
    /// Chain PRs add readers here as their signed decoders become available.
    static let readers: [PositionReading] = [
        SolanaDelegatedAmountReader(),
        SolanaStakeAccountAmountReader(),
        TonStakedPositionReader(),
        TcyStakedPositionReader()
    ]

    /// Resolves through the first reader matching a trusted local coin.
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

/// Reads a THORChain TCY staker's position, for a fractional `tcy-:<bps>` unstake.
struct TcyStakedPositionReader: PositionReading {

    /// Injected so a test needs no network; production reads the staker endpoint.
    var readRaw: (String) async -> Decimal = {
        await ThorchainService.shared.fetchTcyStakedAmount(address: $0)
    }

    func handles(_ decoded: DecodedTransaction, coin: Coin) -> Bool {
        guard coin.chain == .thorChain,
              coin.ticker.uppercased() == "TCY",
              decoded.operation == .unstake,
              decoded.evidence == .memo,
              case .fraction(_, .transactionCoin) = decoded.amount
        else { return false }
        return true
    }

    func amount(for decoded: DecodedTransaction, coin: Coin) async -> HeroCoinAmount? {
        await FractionalWithdrawalAmount.resolve(for: decoded, coin: coin, readStakedRaw: readRaw)
    }
}
