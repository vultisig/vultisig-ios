//
//  BlockchairService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import BigInt
import OSLog

actor BlockchairService {

    /// UTXOs requested per Blockchair page. Matches the SDK's page size, and
    /// the proxy was verified to serve it (and well beyond) unchanged.
    static let defaultUtxoPageSize = 1_000

    /// Hard bound on how many requests the pagination walk will make.
    ///
    /// The walk is fail-loud — it refuses to hand back a partial view — so it
    /// needs a bound, or an address with an enormous UTXO count would hang the
    /// send instead of failing it. The walk ends on a page the provider
    /// couldn't fill, so this supports an address of just under 20 000 UTXOs:
    /// far past anything spendable, since a single standard transaction tops
    /// out near 1 400 P2WPKH inputs at Bitcoin's 100 kvB standardness limit.
    /// It also bounds the worst case at 20 sequential round trips.
    static let defaultMaxUtxoPages = 20

    private let logger = Log.chain.service
    private let httpClient: HTTPClientProtocol
    private let utxoPageSize: Int
    private let maxUtxoPages: Int

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        utxoPageSize: Int = BlockchairService.defaultUtxoPageSize,
        maxUtxoPages: Int = BlockchairService.defaultMaxUtxoPages
    ) {
        self.httpClient = httpClient
        self.utxoPageSize = utxoPageSize
        self.maxUtxoPages = maxUtxoPages
    }

    static let shared = BlockchairService()

    var blockchairData: ThreadSafeDictionary<String, Blockchair> = ThreadSafeDictionary()

    private var cacheFeePrice: [String: (data: BigInt, timestamp: Date)] = [:]

    func fetchBlockchairData(coin: CoinMeta, address: String) async throws -> Blockchair {
        let response = try await fetchBlockchairResponse(coin: coin, address: address)

        guard let d = response.data[address] else {
            throw Errors.fetchBlockchairDataFailed
        }

        blockchairData.set(blockchairKey(for: coin, address: address), d)

        return d
    }

    /// Fetches the full Blockchair dashboard response (data + request
    /// `context`). `fetchBlockchairData` wraps this to return only the
    /// per-address entry; the QBTC claim flow uses the raw response to read
    /// `context.state` (the chain tip) for confirmation counting.
    ///
    /// The `utxo` array is paged: Blockchair caps it at the request's `limit`
    /// and returns it newest-first, so an unpaged fetch hands back a
    /// recency-biased slice with no indication that anything is missing. Pages
    /// are pulled until the address's reported `unspent_output_count` is
    /// covered, then merged into the first page's response.
    ///
    /// The completeness contract is deliberately fail-loud: rather than return
    /// a partial UTXO set — which a large send would happily draw already-spent
    /// inputs from — this throws. Callers on the balance path treat that as a
    /// transient fetch failure and keep the previous balance.
    ///
    /// A chain whose spendable set this service does not serve skips the walk
    /// entirely — see `servesUtxoSet(for:)`.
    func fetchBlockchairResponse(coin: CoinMeta, address: String) async throws -> BlockchairResponse {
        let chainName = coin.chain.name.lowercased()

        guard Self.servesUtxoSet(for: coin.chain) else {
            // One request, no rows. `limit`/`offset` apply to
            // `transactions,utxo` in that order, so pinning both sides to zero
            // returns the `address` aggregate on its own — verified against
            // the proxy on dash, which answers `limit: "0,0"` with `balance`
            // and `unspent_output_count` present and both arrays empty.
            return try await httpClient.request(
                BlockchairAPI.dashboard(address: address, chain: chainName, limit: 0, offset: 0),
                responseType: BlockchairResponse.self
            ).data
        }

        var firstPage: BlockchairResponse?
        var utxos: [Blockchair.BlockchairUtxo] = []
        var seenOutPoints: Set<Blockchair.BlockchairUtxo.OutPoint> = []
        var expectedUtxoCount: Int?

        for pageIndex in 0..<maxUtxoPages {
            let page = try await httpClient.request(
                BlockchairAPI.dashboard(
                    address: address,
                    chain: chainName,
                    limit: utxoPageSize,
                    offset: pageIndex * utxoPageSize
                ),
                responseType: BlockchairResponse.self
            ).data

            let base = firstPage ?? page
            firstPage = base

            guard let entry = page.data[address] else {
                guard pageIndex == 0 else {
                    // The provider acknowledged the address on an earlier page
                    // and has now stopped. Whatever we hold is partial by
                    // construction, and nothing downstream could tell.
                    logger.error(
                        "Blockchair dropped \(chainName) address from page \(pageIndex) after \(utxos.count) UTXOs"
                    )
                    throw Errors.utxoPageMissingAddress(page: pageIndex, retrieved: utxos.count)
                }
                // Nothing was ever returned for this address. Hand the response
                // back untouched so callers keep their own handling of a
                // missing address key.
                return base
            }

            let pageUtxos = entry.utxo ?? []
            for utxo in pageUtxos {
                if let outPoint = utxo.outPoint, !seenOutPoints.insert(outPoint).inserted {
                    continue
                }
                utxos.append(utxo)
            }
            // Offset paging is only sound over a list that holds still: remove
            // one entry and everything after it slides up past an offset we
            // have already walked, leaving a gap no amount of merging can see.
            // The reported count moves with the list, so a change in it between
            // pages is that signal.
            // Every page has to keep reporting the same total: a page that
            // stops reporting one is no more verifiable than a page reporting
            // a different one.
            let pageUtxoCount = entry.address?.unspentOutputCount
            if let expectedUtxoCount, pageUtxoCount != expectedUtxoCount {
                logger.error(
                    "Blockchair UTXO count for \(chainName) moved from \(expectedUtxoCount) to \(pageUtxoCount.map(String.init) ?? "none") mid-walk"
                )
                throw Errors.utxoSetChangedWhilePaging(was: expectedUtxoCount, became: pageUtxoCount)
            }
            expectedUtxoCount = expectedUtxoCount ?? pageUtxoCount
            // A page the provider filled to the requested limit means it may
            // still be holding more.
            let isLastPage = pageUtxos.count < utxoPageSize

            guard let expected = expectedUtxoCount else {
                // No reported total, so there is nothing to verify completeness
                // against. A single short page is still provably whole — we
                // asked for a full page and the provider had less to give. Once
                // more than one page is involved that argument disappears:
                // offset paging skips an entry whenever one is removed between
                // requests, and the final page is short either way.
                if isLastPage, pageIndex == 0 {
                    return Self.replacingUtxos(in: base, address: address, with: utxos)
                }
                logger.error(
                    "Blockchair reported no unspent_output_count for \(chainName) across multiple pages — cannot verify completeness"
                )
                throw Errors.unverifiableUtxoSet(retrieved: utxos.count)
            }

            // Only the end of the list ends the walk. The count is read once,
            // off the first page, so it can be stale or under-report what the
            // provider is actually holding; stopping on it while a page came
            // back full is how a recency-biased partial set would slip through
            // again. It is the check applied on arrival, not the terminator.
            guard isLastPage else { continue }

            if utxos.count < expected {
                // We reached the end of the list and still came up short of what
                // the provider said it holds. Either a page was truncated or the
                // set changed underneath us; both make this snapshot unsafe to
                // build a transaction from.
                logger.error(
                    "Blockchair returned \(utxos.count) of \(expected) UTXOs for \(chainName) — refusing partial set"
                )
                throw Errors.incompleteUtxoSet(expected: expected, retrieved: utxos.count)
            }

            return Self.replacingUtxos(in: base, address: address, with: utxos)
        }

        logger.error(
            "Blockchair UTXO pagination hit the \(self.maxUtxoPages)-page cap for \(chainName) with \(utxos.count) retrieved"
        )
        throw Errors.utxoPageLimitExceeded(pageLimit: maxUtxoPages, retrieved: utxos.count)
    }

    /// Whether this chain's spendable set is the one this service serves.
    ///
    /// Dash's is not. `KeysignPayloadFactory` funds a Dash transaction from a
    /// node's address index (`getaddressutxos`), and the only thing read from
    /// its Blockchair dashboard is `address.balance` — a number that does not
    /// depend on the `utxo` array at all. Walking that array for Dash would buy
    /// nothing and cost everything the walk costs: up to `maxUtxoPages`
    /// sequential round trips on the balance refresh and the send screen, and a
    /// brand-new set of completeness failures able to block both. So Dash asks
    /// for the aggregate alone.
    static func servesUtxoSet(for chain: Chain) -> Bool {
        chain != .dash
    }

    /// Rebuilds `response` with the merged `utxo` array in place of the page's
    /// own. Leaves the response untouched when it carries no entry for
    /// `address`, so a missing-address response stays recognisable as such.
    private static func replacingUtxos(
        in response: BlockchairResponse,
        address: String,
        with utxos: [Blockchair.BlockchairUtxo]
    ) -> BlockchairResponse {
        guard let entry = response.data[address] else { return response }
        var data = response.data
        data[address] = Blockchair(address: entry.address, utxo: utxos)
        return BlockchairResponse(data: data, context: response.context)
    }

    func blockchairKey(for coin: CoinMeta, address: String) -> String {
        return "\(address)-\(coin.chain.name.lowercased())"
    }

    func fetchSatsPrice(coin: Coin) async throws -> BigInt {
        let cacheKey = "utxo-\(coin.chain.name.lowercased())-fee-price"
        if let cachedData: BigInt = Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return cachedData
        }
        let urlString = Endpoint.blockchairStats(coin.chain.name.lowercased()).absoluteString
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        if let result = Utils.extractResultFromJson(fromData: data, path: "data.suggested_transaction_fee_per_byte_sat"),
           let resultNumber = result as? NSNumber {
            let bigIntResult = BigInt(resultNumber.intValue)
            self.cacheFeePrice[cacheKey] = (data: bigIntResult, timestamp: Date())
            return bigIntResult
        } else {
            throw Errors.fetchSatsPriceFailed
        }
    }

    func getByKey(key: String) -> Blockchair? {
        return blockchairData.get(key)
    }

    /// Clear UTXO cache for a specific address to force fresh UTXO fetch
    func clearUTXOCache(for coin: Coin) {
        blockchairData.remove(coin.blockchairKey)
        logger.info("Cleared UTXO cache for \(coin.chain.name) address: \(coin.address)")
    }

}

extension BlockchairService {

    enum Errors: Error {
        case fetchSatsPriceFailed
        case fetchBlockchairDataFailed
        /// Paging reached the end of Blockchair's list with fewer UTXOs than
        /// the address reported holding. Building a transaction from what did
        /// arrive risks selecting an input that no longer exists, so the fetch
        /// fails instead of returning a partial set.
        case incompleteUtxoSet(expected: Int, retrieved: Int)
        /// The address holds more unspent outputs than the page cap allows.
        case utxoPageLimitExceeded(pageLimit: Int, retrieved: Int)
        /// A page after the first came back without the requested address,
        /// after an earlier page had returned UTXOs for it. The walk cannot
        /// continue and what it holds is partial.
        case utxoPageMissingAddress(page: Int, retrieved: Int)
        /// Blockchair reported no `unspent_output_count` and the list spans
        /// more than one page, leaving no signal that the walk saw everything.
        case unverifiableUtxoSet(retrieved: Int)
        /// The address's unspent-output count changed between pages — or a
        /// later page stopped reporting one (`became == nil`). Either way the
        /// list may have moved underneath the offsets the walk already used,
        /// and any gap that opened is invisible from here.
        case utxoSetChangedWhilePaging(was: Int, became: Int?)
    }
}
