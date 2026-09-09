//
//  TonJettonFinder.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Discovers the jettons an account holds, returning only the ones that pass
/// verification.
///
/// TON wallets are carpet-bombed with airdropped counterfeits — fake USDT above
/// all — so auto-adding whatever an account holds would put a "USDT" balance on
/// the home screen that the user never received. Unverified and scam jettons
/// stay addable by hand, where the UI can label them.
struct TonJettonFinder {

    /// Toncenter's page cap for this endpoint.
    static let defaultPageSize = 100

    /// 2000 distinct jettons is far beyond any real wallet. This is the last
    /// resort for a proxy that keeps serving pages; the repeated-master check
    /// below normally stops long before it.
    static let defaultMaxPages = 20

    /// TEP-74's default, and what the SDK and Windows fall back to, so a jetton
    /// whose decimals nobody publishes reads the same on all three platforms.
    static let defaultDecimals = 9

    private let httpClient: HTTPClientProtocol
    private let registryStore: TonJettonRegistryStore
    private let host: URL
    private let pageSize: Int
    private let maxPages: Int

    /// `pageSize` and `maxPages` are injectable so the paging rules can be
    /// tested against a two-row page instead of a hundred-row fixture.
    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        registryStore: TonJettonRegistryStore = .shared,
        host: URL? = nil,
        pageSize: Int = TonJettonFinder.defaultPageSize,
        maxPages: Int = TonJettonFinder.defaultMaxPages
    ) {
        self.httpClient = httpClient
        self.registryStore = registryStore
        self.host = host ?? Self.resolvedHost()
        self.pageSize = pageSize
        self.maxPages = maxPages
    }

    /// Honours the user's TON custom-RPC override (host only; the `/ton/v3`
    /// paths are preserved), matching `TonJettonMetadataResolver`.
    private static func resolvedHost() -> URL {
        guard let override = CustomRPCStore.shared.url(for: .ton),
              let url = URL(string: override) else {
            return TonAPI.defaultHost
        }
        return url
    }

    /// Verified jettons held at `ownerAddress`.
    ///
    /// Throws when the listing cannot be read, so the caller logs a discovery
    /// failure rather than silently concluding the account holds nothing. A
    /// registry that cannot be refreshed is *not* a failure — it degrades to the
    /// curated list and discovery continues with fewer jettons recognised.
    func discover(ownerAddress: String) async throws -> [CoinMeta] {
        guard let owner = TonJettonAddress.canonical(ownerAddress) else { return [] }

        let registry = await registryStore.registry()
        var seenMasters: Set<String> = []
        /// Row identity, recorded before any filtering — see the paging note below.
        var seenWallets: Set<String> = []
        var discovered: [CoinMeta] = []

        for page in 0..<maxPages {
            let response = try await httpClient.request(
                TonAPI(
                    .ownerJettonWallets(
                        ownerAddress: ownerAddress,
                        limit: pageSize,
                        offset: page * pageSize
                    ),
                    host: host
                ),
                responseType: JettonWalletsResponse.self
            ).data

            let masters = TonJettonMasterMetadata.index(from: response.metadata)
            let walletsBeforePage = seenWallets.count

            for wallet in response.jetton_wallets {
                seenWallets.insert(wallet.address)
                guard TonJettonAddress.canonical(wallet.owner) == owner else { continue }
                guard let master = TonJettonAddress.canonical(wallet.jetton) else { continue }
                guard seenMasters.insert(master).inserted else { continue }
                guard let balance = BigInt(wallet.balance), balance > 0 else { continue }

                if let coin = coin(master: master, metadata: masters[master], registry: registry) {
                    discovered.append(coin)
                }
            }

            // A full page that carries no row we have not already seen is the
            // same page served again — what a proxy that ignores `offset` does,
            // and what would otherwise turn one balance into twenty.
            //
            // Replay is judged on the rows, not on what survived the filters: a
            // full page of somebody else's wallets, or of jettons that all
            // failed verification, is a page we must walk *past*, not a reason
            // to stop while later offsets still hold the account's own jettons.
            let isLastPage = response.jetton_wallets.count < pageSize
            let isReplay = seenWallets.count == walletsBeforePage
            if isLastPage || isReplay { break }
        }

        return discovered
    }

    /// The coin for one held master, or `nil` when it must not auto-appear.
    ///
    /// Curated metadata wins outright for jettons we ship ourselves: our Tether
    /// entry carries the ASCII ticker `USDT` and the real 6 decimals, where the
    /// chain and the community whitelist both say `USD₮` and neither publishes
    /// decimals at all.
    private func coin(
        master: String,
        metadata: TonJettonMasterMetadata?,
        registry: TonJettonRegistry
    ) -> CoinMeta? {
        let verification = TonJettonClassifier.classify(
            address: master,
            symbol: metadata?.symbol,
            name: metadata?.name,
            isFlaggedScam: metadata?.isFlaggedScam,
            registry: registry
        )
        guard verification.autoSurfaces, let listed = registry.entry(for: master) else { return nil }

        if listed.verification == .curated {
            return CoinMeta(
                chain: .ton,
                ticker: listed.symbol,
                logo: listed.logo ?? "",
                decimals: listed.decimals ?? Self.defaultDecimals,
                priceProviderId: listed.priceProviderId ?? "",
                contractAddress: listed.address,
                isNativeToken: false
            )
        }

        guard let ticker = metadata?.symbol ?? listed.symbol.trimmedNonEmpty else { return nil }
        return CoinMeta(
            chain: .ton,
            ticker: ticker,
            logo: metadata?.logo ?? listed.logo ?? "",
            decimals: metadata?.decimals ?? listed.decimals ?? Self.defaultDecimals,
            priceProviderId: listed.priceProviderId ?? "",
            contractAddress: listed.address,
            isNativeToken: false
        )
    }
}
