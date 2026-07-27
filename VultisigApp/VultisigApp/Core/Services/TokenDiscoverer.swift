//
//  TokenDiscoverer.swift
//  VultisigApp
//

import Foundation

/// Strategy that auto-discovers the non-native tokens an address holds for a
/// given native coin's chain. Each chain family that supports discovery has a
/// concrete conformer; chains without discovery resolve to `NoTokenDiscoverer`,
/// so "this chain does not discover tokens" is a declared choice rather than a
/// silent fall-through.
@MainActor
protocol TokenDiscoverer {
    func discoverTokens(nativeCoin: CoinMeta, address: String) async throws -> [CoinMeta]
}

// MARK: - Concrete discoverers

/// EVM chains: the per-chain `EvmService` enumerates ERC-20 balances held by
/// `address`.
struct EVMTokenDiscoverer: TokenDiscoverer {
    func discoverTokens(nativeCoin: CoinMeta, address: String) async throws -> [CoinMeta] {
        let service = try EvmService.getService(forChain: nativeCoin.chain)
        return try await service.getTokens(nativeToken: nativeCoin, address: address)
    }
}

struct SolanaTokenDiscoverer: TokenDiscoverer {
    func discoverTokens(nativeCoin _: CoinMeta, address: String) async throws -> [CoinMeta] {
        try await SolanaService.shared.fetchTokens(for: address)
    }
}

struct SuiTokenDiscoverer: TokenDiscoverer {
    func discoverTokens(nativeCoin _: CoinMeta, address: String) async throws -> [CoinMeta] {
        try await SuiService.shared.getAllTokensWithMetadata(address: address)
    }
}

/// THORChain / Chainnet / Stagenet — the network-specific service is resolved
/// through `ThorchainServiceFactory`.
struct ThorchainTokenDiscoverer: TokenDiscoverer {
    func discoverTokens(nativeCoin: CoinMeta, address: String) async throws -> [CoinMeta] {
        let service = ThorchainServiceFactory.getService(for: nativeCoin.chain)
        return try await service.fetchTokens(address)
    }
}

struct MayachainTokenDiscoverer: TokenDiscoverer {
    func discoverTokens(nativeCoin _: CoinMeta, address: String) async throws -> [CoinMeta] {
        try await MayachainService.shared.fetchTokens(address)
    }
}

/// Cosmos bank-denom discovery for the allowlisted chains (Terra + Terra
/// Classic). Only visible (`!isHidden`) denoms land here; hidden-by-default
/// denoms are surfaced through a separate path so they don't pollute the
/// visible coin list.
struct CosmosBankDenomTokenDiscoverer: TokenDiscoverer {
    func discoverTokens(nativeCoin: CoinMeta, address: String) async throws -> [CoinMeta] {
        let discovered = try await CosmosCoinFinder.shared.discoverBankDenoms(
            chain: nativeCoin.chain,
            address: address
        )
        return discovered
            .filter { !$0.isHidden }
            .map { $0.toCoinMeta(chain: nativeCoin.chain) }
    }
}

/// Explicit no-op for chains that do not support token auto-discovery.
/// Registered by name so "no discovery" is a declared choice rather than an
/// implicit empty fall-through.
struct NoTokenDiscoverer: TokenDiscoverer {
    func discoverTokens(nativeCoin _: CoinMeta, address _: String) -> [CoinMeta] {
        []
    }
}

// MARK: - Registry

/// Resolves the `TokenDiscoverer` for a chain. The switch is exhaustive over
/// `ChainType` with no `default`, so adding a new chain family forces an
/// explicit decision here — either declare its discoverer or map it to
/// `NoTokenDiscoverer`.
///
/// Main-actor-isolated because the `TokenDiscoverer` conformers it constructs
/// inherit `@MainActor` from the protocol; the sole caller
/// (`CoinService.fetchDiscoveredTokens`) is already `@MainActor`, so resolution
/// stays a synchronous same-actor call.
@MainActor
enum TokenDiscovererRegistry {
    static func discoverer(for chain: Chain) -> TokenDiscoverer {
        switch chain.chainType {
        case .EVM:
            return EVMTokenDiscoverer()
        case .Solana:
            return SolanaTokenDiscoverer()
        case .Sui:
            return SuiTokenDiscoverer()
        case .THORChain:
            return thorchainFamilyDiscoverer(for: chain)
        case .Cosmos:
            return CosmosCoinFinder.allowlistedChains.contains(chain)
                ? CosmosBankDenomTokenDiscoverer()
                : NoTokenDiscoverer()
        case .UTXO, .Cardano, .Polkadot, .Ton, .Ripple, .Tron:
            return NoTokenDiscoverer()
        }
    }

    /// THORChain-family sub-resolution: the three THORChain networks share the
    /// factory-selected service, MayaChain has its own, and any other
    /// THORChain-type chain declares no discovery.
    private static func thorchainFamilyDiscoverer(for chain: Chain) -> TokenDiscoverer {
        switch chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            return ThorchainTokenDiscoverer()
        case .mayaChain:
            return MayachainTokenDiscoverer()
        default:
            return NoTokenDiscoverer()
        }
    }
}
