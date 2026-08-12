//
//  RateStorage.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.08.2024.
//

import Foundation
import Combine
import SwiftData
import OSLog

final class RateProvider {

    enum CryptoId {
        case priceProvider(String)
        case contract(String)

        var id: String {
            switch self {
            case .priceProvider(let value):
                return value
            case .contract(let value):
                return value
            }
        }
    }

    static let shared = RateProvider()

    /// Fires on the main actor whenever the cached rate set changes — the initial
    /// load of persisted rates and every `save(rates:)`.
    ///
    /// Rates are an otherwise silent cache: callers that render a *precomputed*
    /// fiat value (rather than reading `rate(for:)` inside `body`) have no way to
    /// learn that a rate arrived, so their fiat stays frozen at whatever was
    /// cached when they last recomputed. This signal is that missing link.
    let ratesDidChange = PassthroughSubject<Void, Never>()

    static func cryptoId(for coin: CoinMeta) -> CryptoId {
        switch coin.chain.chainType {
        case .Sui:
            if coin.isNativeToken || !coin.priceProviderId.isEmpty {
                return .priceProvider(coin.priceProviderId)
            } else {
                return .contract(SuiCoinType.rateKey(coin.contractAddress))
            }
        case .EVM, .Solana, .THORChain:
            if coin.isNativeToken || !coin.priceProviderId.isEmpty {
                return .priceProvider(coin.priceProviderId)
            } else {
                return .contract(coin.contractAddress)
            }
        default:
            return .priceProvider(coin.priceProviderId)
        }
    }

    /// Should be updated manually - thread-safe backing storage, keyed by
    /// `Rate.id`.
    ///
    /// A dictionary rather than a `Set<Rate>`: `rate(for:)` is on the path of
    /// every fiat render in the app (wallet list, send, swap, DeFi, coin
    /// detail) and looking a rate up in a set by `id` means `first(where:)` —
    /// a linear scan of every cached rate, not a hash probe. `DatabaseRate.id`
    /// is `@Attribute(.unique)`, so one entry per identifier is also the
    /// storage model the persisted rates already follow.
    private var _rates = [String: Rate]()
    private var ratesLock = os_unfair_lock()

    /// Thread-safe single-rate lookup.
    private func cachedRate(id: String) -> Rate? {
        os_unfair_lock_lock(&ratesLock)
        defer { os_unfair_lock_unlock(&ratesLock) }
        return _rates[id]
    }

    /// Thread-safe wholesale replacement of the cache.
    private func replaceRates(with newRates: [Rate]) {
        let replacement = Dictionary(newRates.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        os_unfair_lock_lock(&ratesLock)
        defer { os_unfair_lock_unlock(&ratesLock) }
        _rates = replacement
    }

    /// Thread-safe newest-wins merge: an incoming rate replaces the cached one
    /// with the same identifier and leaves every other entry untouched.
    private func mergeRates(_ newRates: [Rate]) {
        os_unfair_lock_lock(&ratesLock)
        defer { os_unfair_lock_unlock(&ratesLock) }
        for rate in newRates {
            _rates[rate.id] = rate
        }
    }

    private init() {
        // Defer fetch to avoid re-entrant SwiftData calls during init.
        // Must run on MainActor — ModelContext is MainActor-isolated.
        Task { @MainActor [weak self] in
            self?.loadPersistedRates()
        }
    }

    /// Populates the cache from the persisted rates.
    ///
    /// Called once, from `init`. Not `private` because the initializer of a
    /// process-wide singleton cannot be re-entered from a test, and the
    /// non-finite filter below is worth verifying rather than asserting.
    @MainActor
    func loadPersistedRates() {
        let descriptor = FetchDescriptor<DatabaseRate>()
        do {
            let objects = try Storage.shared.modelContext.fetch(descriptor)
            // The same non-finite filter `save(rates:)` applies, on the way back
            // in: a build predating that filter could have persisted an infinity,
            // and this is the one path that would put it back into the cache
            // every fiat render reads. Filtered rather than deleted — a
            // launch-time store write is exactly the kind of gratuitous mutation
            // these guards exist to stop making, and the row is overwritten by
            // the next finite quote for that coin anyway.
            replaceRates(with: objects.map { Rate(object: $0) }.filter { $0.value.isFinite })
            // Persisted rates make fiat renderable immediately on a warm
            // start; announce them so views that cached a pre-load fiat
            // value recompute instead of waiting on a network refresh.
            ratesDidChange.send()
        } catch {
            Log.chain.service.error("Failed to load rates: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fiatBalance(value: Decimal, rate: Rate) -> Decimal {
        let result = value * Decimal(rate.value)
        // Don't truncate here - let the formatter handle precision
        return result
    }

    func fiatBalance(value: Decimal, coin: Coin, currency: SettingsCurrency = .current) -> Decimal {
        fiatBalance(value: value, coin: coin.toCoinMeta(), currency: currency)
    }

    func fiatBalance(value: Decimal, coin: CoinMeta, currency: SettingsCurrency = .current) -> Decimal {
        guard let rate = rate(for: coin, currency: currency) else {
            return .zero
        }
        return fiatBalance(value: value, rate: rate)
    }

    func fiatBalanceString(value: Decimal, coin: Coin, currency: SettingsCurrency = .current) -> String {
        let balance = fiatBalance(value: value, coin: coin.toCoinMeta(), currency: currency)
        return balance.formatToFiat(includeCurrencySymbol: true)
    }

    /// Format fiat balance for fee display with more decimal places (e.g., $0.0065 instead of $0.00)
    func fiatFeeString(value: Decimal, coin: Coin, currency: SettingsCurrency = .current) -> String {
        let balance = fiatBalance(value: value, coin: coin.toCoinMeta(), currency: currency)
        return balance.formatToFiatForFee(includeCurrencySymbol: true)
    }

    func rate(for coin: Coin, currency: SettingsCurrency = .current) -> Rate? {
        rate(for: coin.toCoinMeta(), currency: currency)
    }

    func rate(for coin: CoinMeta, currency: SettingsCurrency = .current) -> Rate? {
        let cryptoId = RateProvider.cryptoId(for: coin)
        let identifier = Rate.identifier(fiat: currency.rawValue, crypto: cryptoId.id)
        return cachedRate(id: identifier)
    }

    func hasRate(for coin: Coin, currency: SettingsCurrency = .current) -> Bool {
        rate(for: coin, currency: currency) != nil
    }

    func hasRate(for coin: CoinMeta, currency: SettingsCurrency = .current) -> Bool {
        rate(for: coin, currency: currency) != nil
    }

    @MainActor func save(rates newRates: [Rate]) throws {
        // A non-finite rate is never a usable price, and admitting one poisons
        // the cache every fiat render reads. NaN is worse still: `NaN != NaN`, so
        // no equality guard can ever suppress it, and the attribute coerces it to
        // `0` on save (infinities persist as they are), so the stored value never
        // compares equal to the incoming one either — one NaN quote re-dirties
        // its row on every refresh from then on, notifying every observer, and
        // through the save every `@Query` in the app, about a price that never
        // changed. Nothing upstream rejects one: the MAYAChain pool-derived price
        // is `Double(String)` arithmetic over API-supplied balances, and
        // `Double("nan")` parses. Dropped at the door so the last usable price
        // survives in both the cache and the store.
        let rates = newRates.filter { $0.value.isFinite }

        // if a rate is newer , we use the newer one
        mergeRates(rates)

        // The in-memory cache is what rendering reads, and it has already
        // changed — announce it even if the persistence below throws, or a
        // failed write would leave the UI showing fiat that contradicts the
        // cache until the next refresh.
        defer { ratesDidChange.send() }

        // Update existing or insert new rates
        for rate in rates {
            let rateId = rate.id // Capture the value outside the predicate
            let descriptor = FetchDescriptor<DatabaseRate>(
                predicate: #Predicate { $0.id == rateId }
            )

            if let existingRate = try Storage.shared.modelContext.fetch(descriptor).first {
                update(existingRate, from: rate)
            } else {
                // Insert new rate
                Storage.shared.insert(rate.mapToObject())
            }
        }

        try Storage.shared.modelContext.save()
    }

    /// Copies a refreshed rate onto its persisted row, or leaves the row entirely
    /// alone when nothing differs.
    ///
    /// The equality guard is load-bearing, not an optimization. SwiftData's
    /// `@Model` setter wraps each store in `withMutation(of:)`, which notifies
    /// observers **without comparing** the new value to the old, and a save then
    /// posts a store-change notification that re-evaluates every `@Query` in the
    /// app — including queries over entirely unrelated types. So "nothing reads
    /// `DatabaseRate`" is not a defence: a blind re-assignment here invalidates
    /// the whole window, and this is the app's largest write burst — one row per
    /// held coin, on every price refresh, most of them unchanged.
    ///
    /// The guard is all-or-nothing over every write below, and it must compare
    /// **every** field that is assigned, or an uncompared field re-opens the same
    /// hole. Add to both lists together.
    @MainActor
    private func update(_ object: DatabaseRate, from rate: Rate) {
        guard object.fiat != rate.fiat
            || object.crypto != rate.crypto
            || object.value != rate.value
        else { return }

        object.fiat = rate.fiat
        object.crypto = rate.crypto
        object.value = rate.value
    }
}
