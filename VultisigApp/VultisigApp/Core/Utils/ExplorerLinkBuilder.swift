//
//  ExplorerLinkBuilder.swift
//  VultisigApp
//

import Foundation

/// Single source of truth for "View on Explorer" / "View Progress" URLs across
/// the app. Maps either an integration identity (a stored provider string, a
/// runtime `SwapQuote`, or a keysign `SwapPayload`) to the appropriate tracker
/// URL — LI.FI scanner, THORChain RuneScan, MayaChain explorer — or falls back
/// to the canonical chain explorer (`getExplorerURL`) so behaviour stays
/// consistent everywhere a tx URL is shown.
enum ExplorerLinkBuilder {

    // MARK: - High-level overloads

    static func url(for transaction: TransactionHistoryData) -> URL? {
        url(
            provider: transaction.swapProvider,
            txHash: transaction.txHash,
            chainRawValue: transaction.chainRawValue,
            fallbackExplorerLink: transaction.explorerLink
        )
    }

    /// Used by `SwapCryptoLogic.progressLink` (and any post-swap success view).
    /// Returns a `String?` to match the existing call-site signature.
    static func progressLink(quote: SwapQuote?, txHash: String, fromChain: Chain) -> String? {
        let provider = quote.map { swapProvider(for: $0, sourceChain: fromChain) }
        return trackerURL(for: provider, txHash: txHash, sourceChain: fromChain)
            ?? getExplorerURL(chain: fromChain, txid: txHash)
    }

    /// Used by `KeysignViewModel.getSwapProgressURL`.
    /// Returns a `String?` to match the existing call-site signature.
    static func progressLink(swapPayload: SwapPayload?, txHash: String) -> String? {
        guard let swapPayload else { return nil }
        let sourceChain = swapPayload.fromCoin.chain
        return trackerURL(for: swapProvider(for: swapPayload), txHash: txHash, sourceChain: sourceChain)
            ?? getExplorerURL(chain: sourceChain, txid: txHash)
    }

    // MARK: - Lower-level resolver (used by tx-history sheet + tests)

    static func url(
        provider: String?,
        txHash: String,
        chainRawValue: String,
        fallbackExplorerLink: String
    ) -> URL? {
        let sourceChain = Chain(rawValue: chainRawValue)
        if let provider = legacySwapProvider(from: provider, chainRawValue: chainRawValue),
           let tracker = trackerURL(for: provider, txHash: txHash, sourceChain: sourceChain) {
            return URL(string: tracker)
        }
        if let sourceChain {
            return URL(string: getExplorerURL(chain: sourceChain, txid: txHash))
        }
        return URL(string: fallbackExplorerLink)
    }

    // MARK: - Provider → tracker resolver

    /// The single provider→tracker mapping shared by all three entry points
    /// (persisted history string, live `SwapQuote`, keysign `SwapPayload`). Each
    /// entry point resolves its own identity to a `SwapProvider`, then this is
    /// the one place that maps a provider to its integration tracker — so adding
    /// or renaming a tracked provider happens in exactly one switch.
    ///
    /// Returns `nil` when the provider has no dedicated tracker (aggregator /
    /// Jupiter / unknown routes), so the caller falls back to the canonical chain
    /// explorer. `sourceChain` is the from-chain — only SwapKit reads it, to
    /// append the chainId hint.
    private static func trackerURL(
        for provider: SwapProvider?,
        txHash: String,
        sourceChain: Chain?
    ) -> String? {
        guard let provider else { return nil }
        switch provider {
        case .thorchain:
            return thorchainTracker(txid: txHash)
        case .thorchainChainnet:
            return thorchainChainnetTracker(txid: txHash)
        case .thorchainStagenet:
            return thorchainStagenetTracker(txid: txHash)
        case .mayachain:
            return mayaTracker(txid: txHash)
        case .lifi:
            return lifiTracker(txid: txHash)
        case .swapkit:
            return swapkitTracker(txid: txHash, chain: sourceChain)
        case .oneinch, .kyberswap, .jupiter:
            // Pure aggregators (and Jupiter) have no dedicated tracker; the tx
            // shows on the source chain's canonical explorer instead.
            return nil
        }
    }

    /// Maps a live `SwapQuote` to its `SwapProvider`. Every case maps, so the
    /// tracker decision stays entirely in `trackerURL(for:)`.
    private static func swapProvider(for quote: SwapQuote, sourceChain: Chain) -> SwapProvider {
        switch quote {
        case .thorchain: return .thorchain
        case .thorchainChainnet: return .thorchainChainnet
        case .thorchainStagenet: return .thorchainStagenet
        case .mayachain: return .mayachain
        case .lifi: return .lifi
        case .swapkit: return .swapkit
        case .oneinch: return .oneinch(sourceChain)
        case .kyberswap: return .kyberswap(sourceChain)
        case .jupiter: return .jupiter
        }
    }

    /// Maps a keysign `SwapPayload` to its `SwapProvider`. An unrecognised
    /// generic provider yields `nil` so it falls back to the chain explorer,
    /// matching the pre-refactor behaviour.
    private static func swapProvider(for payload: SwapPayload) -> SwapProvider? {
        switch payload {
        case .thorchain: return .thorchain
        case .thorchainChainnet: return .thorchainChainnet
        case .thorchainStagenet: return .thorchainStagenet
        case .mayachain: return .mayachain
        case .swapkit: return .swapkit
        case .generic(let payload):
            switch payload.provider {
            case .lifi: return .lifi
            case .swapkit: return .swapkit
            case .oneInch: return .oneinch(payload.fromCoin.chain)
            case .kyberSwap: return .kyberswap(payload.fromCoin.chain)
            case .jupiter: return .jupiter
            case .unknown: return nil
            }
        }
    }

    // MARK: - Legacy persisted-string aliases

    /// Maps a persisted/history provider string (Transaction History stores only
    /// the display name) to its `SwapProvider`. Every value `SwapQuote.displayName`
    /// and `SwapPayload.providerName` can produce normalizes to one of these keys,
    /// plus the legacy `"thorswap"`/`"mayachain"`/`"mayaprotocol"` strings from
    /// older history entries. Keys are normalized — lowercased, letters and digits
    /// only — so `"LI.FI"`, `"Maya protocol"` and `"THORChain-Stagenet"` each
    /// collapse to a single key.
    private static let legacyProviderAliases: [String: SwapProvider] = [
        "lifi": .lifi,
        "swapkit": .swapkit,
        "maya": .mayachain,
        "mayachain": .mayachain,
        "mayaprotocol": .mayachain,
        "thorchainstagenet": .thorchainStagenet,
        "thorchainchainnet": .thorchainChainnet,
        "thorchain": .thorchain,
        "thorswap": .thorchain
    ]

    /// Resolves a raw persisted provider string to its `SwapProvider`, applying
    /// the same normalization the alias table is keyed on. The persisted
    /// `"thorchain"`/`"thorswap"` strings carry no network variant, so the
    /// record's chain disambiguates them into chainnet/stagenet.
    private static func legacySwapProvider(from provider: String?, chainRawValue: String) -> SwapProvider? {
        guard let normalized = provider?
            .lowercased()
            .filter({ $0.isLetter || $0.isNumber }),
            let resolved = legacyProviderAliases[normalized] else {
            return nil
        }
        guard resolved == .thorchain else { return resolved }
        if chainRawValue == Chain.thorChainChainnet.rawValue {
            return .thorchainChainnet
        }
        if chainRawValue == Chain.thorChainStagenet.rawValue {
            return .thorchainStagenet
        }
        return .thorchain
    }

    // MARK: - Chain explorer URL

    static func getExplorerURL(chain: Chain, txid: String) -> String {
        explorers[chain]?.tx(txid) ?? ""
    }

    // MARK: - Chain address explorer URL

    static func getExplorerByAddressURL(chain: Chain, address: String) -> String? {
        explorers[chain]?.address(address)
    }

    // MARK: - Explorer registry

    /// A chain's explorer URL builders. One host lives in exactly one place;
    /// every chain→explorer lookup in the app reads from `explorers`.
    struct ExplorerConfig {
        /// Transaction page for a tx hash.
        let tx: (String) -> String
        /// Holder / account page for an address.
        let address: (String) -> String
        /// Contract / token page for a token's contract address, when the chain
        /// exposes one. `nil` means the chain has no dedicated token page — a
        /// token then falls back to the holder's address page (see
        /// `Endpoint.getExplorerByCoinURL`).
        let token: ((String) -> String)?

        init(
            tx: @escaping (String) -> String,
            address: @escaping (String) -> String,
            token: ((String) -> String)? = nil
        ) {
            self.tx = tx
            self.address = address
            self.token = token
        }
    }

    /// Single source of truth mapping each `Chain` to its explorer URL builders.
    /// `getExplorerURL`, `getExplorerByAddressURL`, `Endpoint.getExplorerByCoinURL`
    /// and `Endpoint.getExplorerByAddressURLByGroup` are all lookups into this table.
    static let explorers: [Chain: ExplorerConfig] = [
        .bitcoin: ExplorerConfig(
            tx: { "https://mempool.space/tx/\($0)" },
            address: { "https://mempool.space/address/\($0)" }
        ),
        .bitcoinCash: ExplorerConfig(
            tx: { "https://blockchair.com/bitcoin-cash/transaction/\($0)" },
            address: { "https://blockchair.com/bitcoin-cash/address/\($0)" }
        ),
        .litecoin: ExplorerConfig(
            tx: { "https://blockchair.com/litecoin/transaction/\($0)" },
            address: { "https://blockchair.com/litecoin/address/\($0)" }
        ),
        .dogecoin: ExplorerConfig(
            tx: { "https://blockchair.com/dogecoin/transaction/\($0)" },
            address: { "https://blockchair.com/dogecoin/address/\($0)" }
        ),
        .dash: ExplorerConfig(
            tx: { "https://blockchair.com/dash/transaction/\($0)" },
            address: { "https://blockchair.com/dash/address/\($0)" }
        ),
        .zcash: ExplorerConfig(
            tx: { "https://blockchair.com/zcash/transaction/\($0)" },
            address: { "https://blockchair.com/zcash/address/\($0)" }
        ),
        .thorChain: ExplorerConfig(
            tx: { "https://runescan.io/tx/\($0.stripHexPrefix())" },
            address: { "https://runescan.io/address/\($0)" }
        ),
        .thorChainChainnet: ExplorerConfig(
            tx: { "https://runescan.io/tx/\($0.stripHexPrefix())?network=chainnet" },
            address: { "https://runescan.io/address/\($0)?network=chainnet" }
        ),
        .thorChainStagenet: ExplorerConfig(
            tx: { "https://runescan.io/tx/\($0.stripHexPrefix())?network=stagenet" },
            address: { "https://runescan.io/address/\($0)?network=stagenet" }
        ),
        .solana: ExplorerConfig(
            tx: { "https://orb.helius.dev/tx/\($0)" },
            address: { "https://orb.helius.dev/address/\($0)" },
            token: { "https://orb.helius.dev/address/\($0)" }
        ),
        .ethereum: ExplorerConfig(
            tx: { "https://etherscan.io/tx/\($0)" },
            address: { "https://etherscan.io/address/\($0)" },
            token: { "https://etherscan.io/token/\($0)" }
        ),
        .ethereumSepolia: ExplorerConfig(
            tx: { "https://sepolia.etherscan.io/tx/\($0)" },
            address: { "https://sepolia.etherscan.io/address/\($0)" },
            token: { "https://sepolia.etherscan.io/token/\($0)" }
        ),
        .gaiaChain: ExplorerConfig(
            tx: { "https://www.mintscan.io/cosmos/tx/\($0)" },
            address: { "https://www.mintscan.io/cosmos/address/\($0)" }
        ),
        .dydx: ExplorerConfig(
            tx: { "https://www.mintscan.io/dydx/tx/\($0)" },
            address: { "https://www.mintscan.io/dydx/address/\($0)" }
        ),
        .avalanche: ExplorerConfig(
            tx: { "https://snowtrace.io/tx/\($0)" },
            address: { "https://snowtrace.io/address/\($0)" },
            token: { "https://snowtrace.io/token/\($0)" }
        ),
        .bscChain: ExplorerConfig(
            tx: { "https://bscscan.com/tx/\($0)" },
            address: { "https://bscscan.com/address/\($0)" },
            token: { "https://bscscan.com/token/\($0)" }
        ),
        .mayaChain: ExplorerConfig(
            tx: { "https://www.explorer.mayachain.info/tx/\($0)" },
            address: { "https://www.explorer.mayachain.info/address/\($0)" }
        ),
        .arbitrum: ExplorerConfig(
            tx: { "https://arbiscan.io/tx/\($0)" },
            address: { "https://arbiscan.io/address/\($0)" },
            token: { "https://arbiscan.io/token/\($0)" }
        ),
        .base: ExplorerConfig(
            tx: { "https://basescan.org/tx/\($0)" },
            address: { "https://basescan.org/address/\($0)" },
            token: { "https://basescan.org/token/\($0)" }
        ),
        .optimism: ExplorerConfig(
            tx: { "https://optimistic.etherscan.io/tx/\($0)" },
            address: { "https://optimistic.etherscan.io/address/\($0)" },
            token: { "https://optimistic.etherscan.io/token/\($0)" }
        ),
        .polygon: ExplorerConfig(
            tx: { "https://polygonscan.com/tx/\($0)" },
            address: { "https://polygonscan.com/address/\($0)" },
            token: { "https://polygonscan.com/token/\($0)" }
        ),
        .polygonV2: ExplorerConfig(
            tx: { "https://polygonscan.com/tx/\($0)" },
            address: { "https://polygonscan.com/address/\($0)" },
            token: { "https://polygonscan.com/token/\($0)" }
        ),
        .blast: ExplorerConfig(
            tx: { "https://blastscan.io/tx/\($0)" },
            address: { "https://blastscan.io/address/\($0)" },
            token: { "https://blastscan.io/token/\($0)" }
        ),
        .cronosChain: ExplorerConfig(
            tx: { "https://cronoscan.com/tx/\($0)" },
            address: { "https://cronoscan.com/address/\($0)" },
            token: { "https://cronoscan.com/token/\($0)" }
        ),
        .sui: ExplorerConfig(
            tx: { "https://suiscan.xyz/mainnet/tx/\($0)" },
            address: { "https://suiscan.xyz/mainnet/address/\($0)" },
            token: { "https://suiscan.xyz/mainnet/coin/\($0)" }
        ),
        .polkadot: ExplorerConfig(
            tx: { "https://assethub-polkadot.subscan.io/extrinsic/\($0)" },
            address: { "https://assethub-polkadot.subscan.io/account/\($0)" }
        ),
        .bittensor: ExplorerConfig(
            tx: {
                let hash = $0.hasPrefix("0x") ? $0 : "0x\($0)"
                return "https://taostats.io/extrinsic/\(hash)"
            },
            address: { "https://taostats.io/account/\($0)" }
        ),
        .zksync: ExplorerConfig(
            tx: { "https://explorer.zksync.io/tx/\($0)" },
            address: { "https://explorer.zksync.io/address/\($0)" },
            token: { "https://explorer.zksync.io/token/\($0)" }
        ),
        .ton: ExplorerConfig(
            tx: { "https://tonviewer.com/transaction/\($0)" },
            address: { "https://tonviewer.com/\($0)" },
            token: { "https://tonviewer.com/\($0)" }
        ),
        .osmosis: ExplorerConfig(
            tx: { "https://www.mintscan.io/osmosis/tx/\($0)" },
            address: { "https://www.mintscan.io/osmosis/address/\($0)" }
        ),
        .terra: ExplorerConfig(
            tx: { "https://www.mintscan.io/terra/tx/\($0)" },
            address: { "https://www.mintscan.io/terra/address/\($0)" }
        ),
        .terraClassic: ExplorerConfig(
            tx: { "https://finder.terra.money/classic/tx/\($0)" },
            address: { "https://finder.terra.money/classic/address/\($0)" }
        ),
        .noble: ExplorerConfig(
            tx: { "https://www.mintscan.io/noble/tx/\($0)" },
            address: { "https://www.mintscan.io/noble/address/\($0)" }
        ),
        .ripple: ExplorerConfig(
            tx: { "https://xrpscan.com/tx/\($0)" },
            address: { "https://xrpscan.com/account/\($0)" }
        ),
        .akash: ExplorerConfig(
            tx: { "https://www.mintscan.io/akash/tx/\($0)" },
            address: { "https://www.mintscan.io/akash/address/\($0)" }
        ),
        .tron: ExplorerConfig(
            tx: { "https://tronscan.org/#/transaction/\($0)" },
            address: { "https://tronscan.org/#/address/\($0)" },
            token: { "https://tronscan.org/#/token20/\($0)" }
        ),
        .cardano: ExplorerConfig(
            tx: { "https://cardanoscan.io/transaction/\($0)" },
            address: { "https://cardanoscan.io/address/\($0)" },
            token: { "https://cardanoscan.io/token/\($0)" }
        ),
        .mantle: ExplorerConfig(
            tx: { "https://explorer.mantle.xyz/tx/\($0)" },
            address: { "https://mantlescan.xyz/address/\($0)" },
            token: { "https://mantlescan.xyz/token/\($0)" }
        ),
        .hyperliquid: ExplorerConfig(
            tx: { "https://hypurrscan.io/tx/\($0)" },
            address: { "https://hypurrscan.io/address/\($0)" },
            token: { "https://hypurrscan.io/token/\($0)" }
        ),
        .sei: ExplorerConfig(
            tx: { "https://seiscan.io/tx/\($0)" },
            address: { "https://seiscan.io/address/\($0)" },
            token: { "https://seiscan.io/token/\($0)" }
        ),
        .robinhood: ExplorerConfig(
            tx: { "https://robinhoodchain.blockscout.com/tx/\($0)" },
            address: { "https://robinhoodchain.blockscout.com/address/\($0)" },
            token: { "https://robinhoodchain.blockscout.com/token/\($0)" }
        ),
        .qbtc: ExplorerConfig(
            tx: { "https://explorer.qbtc.net/qbtc/tx/\($0)" },
            address: { "https://explorer.qbtc.net/qbtc/account/\($0)" }
        )
    ]

    // MARK: - Private integration tracker URL builders
    // Hosts and path shapes match the canonical chain-explorer URLs above;
    // LI.FI is unique because it's a cross-chain aggregator scanner with no
    // chain-explorer equivalent.

    private static func lifiTracker(txid: String) -> String {
        "https://scan.li.fi/tx/\(txid)"
    }

    /// `track.swapkit.dev` resolves a hash faster when it knows which chain
    /// to look on, so we append the SwapKit chainId whenever the source chain
    /// maps to one. Falls back to the hash-only link for chains outside the
    /// SwapKit route catalogue.
    private static func swapkitTracker(txid: String, chain: Chain?) -> String {
        let base = "https://track.swapkit.dev/?hash=\(txid)"
        guard let chain, let chainId = SwapKitChainIdentifier.chainId(for: chain) else {
            return base
        }
        return "\(base)&chainId=\(chainId)"
    }

    private static func mayaTracker(txid: String) -> String {
        "https://www.explorer.mayachain.info/tx/\(txid.stripHexPrefix())"
    }

    private static func thorchainTracker(txid: String) -> String {
        "https://runescan.io/tx/\(txid.stripHexPrefix())"
    }

    private static func thorchainChainnetTracker(txid: String) -> String {
        "https://runescan.io/tx/\(txid.stripHexPrefix())?network=chainnet"
    }

    private static func thorchainStagenetTracker(txid: String) -> String {
        "https://runescan.io/tx/\(txid.stripHexPrefix())?network=stagenet"
    }
}
