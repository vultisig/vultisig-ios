//
//  SecuredWithdrawDataSource.swift
//  VultisigApp
//
//  The three live readings the SECURE- form depends on, behind one seam so the
//  form's rules — which secured assets exist, and how small a redemption the
//  outbound fee would swallow — can be exercised without a network.
//

import Foundation

@MainActor
protocol SecuredWithdrawDataSource {
    /// Every bank balance the THORChain account holds. The caller picks the
    /// secured denoms out of it; the raw list is returned so a denom the app
    /// does not yet recognise is filtered by one rule in one place.
    func securedAssetBalances(address: String, chain: Chain) async throws -> [CosmosBalance]

    /// THORChain's advertised outbound fee for an L1 chain, expressed in that
    /// chain's own native units (the endpoint reports 1e8 base units).
    /// `nil` when the chain has no inbound row or the value cannot be read —
    /// the caller treats that as "no threshold known", never as "zero".
    func outboundFee(forInboundChain chainName: String) async -> Decimal?

    /// Fiat value of `amount` units of `coin`, in the user's currency. The
    /// threshold crosses assets — an L1 fee against a secured balance — so it
    /// can only be compared through a common unit.
    func fiatValue(of amount: Decimal, coin: Coin) -> Decimal
}

struct LiveSecuredWithdrawDataSource: SecuredWithdrawDataSource {

    func securedAssetBalances(address: String, chain: Chain) async throws -> [CosmosBalance] {
        try await ThorchainServiceFactory.getService(for: chain).fetchBalances(address)
    }

    func outboundFee(forInboundChain chainName: String) async -> Decimal? {
        let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
        guard
            let inbound = addresses.first(where: { $0.chain.caseInsensitiveCompare(chainName) == .orderedSame }),
            let feeRaw = inbound.outbound_fee,
            let feeBaseUnits = Decimal(string: feeRaw)
        else {
            return nil
        }
        // `/inbound_addresses` reports every chain's outbound fee in fixed 1e8
        // base units regardless of the chain's own decimals.
        return feeBaseUnits / pow(10, 8)
    }

    func fiatValue(of amount: Decimal, coin: Coin) -> Decimal {
        RateProvider.shared.fiatBalance(value: amount, coin: coin)
    }
}
