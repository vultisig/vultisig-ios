//
//  MayaPendingLPPresentation.swift
//  VultisigApp
//
//  What the pending half-deposit card says and whether it can offer to complete
//  the missing side. Pure functions over values so the rules are testable
//  without a view.
//

import Foundation

enum MayaPendingLPPresentation {

    /// MayaChain's average block time, rounded down so the countdown never
    /// promises more time than the deposit has.
    private static let blockMilliseconds: Int64 = 5_800

    static func refundSeconds(blocks: Int64) -> Int64 {
        blocks * blockMilliseconds / 1_000
    }

    /// Days and hours while a day or more remains; otherwise hours and minutes,
    /// because someone half an hour from losing a deposit needs the minutes
    /// rather than a rounded "soon".
    static func refundText(seconds: Int64) -> String {
        let totalMinutes = seconds / 60
        let totalHours = totalMinutes / 60
        let days = totalHours / 24
        let hours = totalHours % 24
        let minutes = totalMinutes % 60
        if days > 0 {
            return String(format: "lpPendingDurationDaysHours".localized, Int(days), Int(hours))
        }
        return String(format: "lpPendingDurationHoursMinutes".localized, Int(hours), Int(minutes))
    }

    static func refundText(blocks: Int64?) -> String {
        guard let blocks else { return "lpPendingRefundTimeUnknown".localized }
        return refundText(seconds: refundSeconds(blocks: blocks))
    }

    /// The side the user still owes: CACAO is `coin1` of a position, the asset
    /// `coin2`.
    static func awaitedSide(of deposit: MayaPendingLPDeposit) -> LPDepositSide {
        deposit.isCacaoPending ? .coin2 : .coin1
    }

    /// Whether the app can send the missing half: only into a pool it pairs, and
    /// only from an account the vault holds on that half's chain.
    @MainActor
    static func canComplete(_ deposit: MayaPendingLPDeposit, in vault: Vault) -> Bool {
        guard MayaLPPools.isPairable(pool: deposit.pool) else { return false }
        switch awaitedSide(of: deposit) {
        case .coin1:
            return vault.nativeCoin(for: .mayaChain) != nil
        case .coin2:
            return ThorchainLPPoolCatalog.depositCoin(forPool: deposit.pool, in: vault.coins) != nil
        }
    }

    static func assetAmount(fixedPoint: Decimal) -> Decimal {
        fixedPoint / Decimal(sign: .plus, exponent: 8, significand: 1)
    }

    static func cacaoAmount(baseUnits: Decimal) -> Decimal {
        baseUnits / Decimal(sign: .plus, exponent: 10, significand: 1)
    }

    struct Card: Equatable, Identifiable {
        let poolId: String
        let title: String
        let awaitedTicker: String
        let awaitedCoin: CoinMeta?
        let depositedAmount: String
        let pairedAddress: String?
        let refundsIn: String
        let protocolName: String

        var id: String { poolId }
    }

    static func card(for deposit: MayaPendingLPDeposit) -> Card {
        let assetCoin = THORChainAssetFactory.createCoin(from: deposit.pool)
        let cacaoCoin = TokensStore.cacao
        let assetTicker = assetCoin?.ticker ?? deposit.pool.split(separator: ".").last.map(String.init) ?? deposit.pool

        let awaitedCoin = deposit.isCacaoPending ? assetCoin : cacaoCoin
        let awaitedTicker = deposit.isCacaoPending ? assetTicker : cacaoCoin.ticker
        let deposited = deposit.isCacaoPending
            ? AmountFormatter.formatCryptoAmount(value: cacaoAmount(baseUnits: deposit.pendingCacao), ticker: cacaoCoin.ticker)
            : AmountFormatter.formatCryptoAmount(value: assetAmount(fixedPoint: deposit.pendingAsset), ticker: assetTicker)

        return Card(
            poolId: deposit.pool,
            title: String(format: "lpPendingTitle".localized, awaitedTicker),
            awaitedTicker: awaitedTicker,
            awaitedCoin: awaitedCoin,
            depositedAmount: deposited,
            pairedAddress: deposit.pairedAddress?.truncatedAddress,
            refundsIn: refundText(blocks: deposit.blocksUntilRefund),
            protocolName: Chain.mayaChain.name
        )
    }
}
