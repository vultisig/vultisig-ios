//
//  CustomTokenResolver.swift
//  VultisigApp
//

import Foundation

/// Resolves a user-pasted contract/token identifier for the custom-token flow.
///
/// Each chain family has its own resolution and validation rules (THORChain bank
/// denoms, Cardano native-token asset ids, Cosmos CW20 contracts, Solana SPL mints,
/// and the shared EVM/Tron/TON `(name, symbol, decimals)` lookup). A concrete
/// resolver bundles both seams for one family so the ViewModel stays chain-agnostic.
///
/// Conventions shared by every conformer:
/// - `fetchInfo` returns `nil` when the input is *definitively* not a token on this
///   chain (wallet address, unknown/non-token contract), which the caller surfaces
///   as "token not found".
/// - Transport failures (rate limiting, network errors) are thrown so the caller can
///   distinguish "try again later" from "not found".
protocol CustomTokenResolver {
    func fetchInfo(contract: String) async throws -> CoinMeta?
    func validate(_ address: String) -> Bool

    /// Whether a resolved token additionally requires the vault to already hold the
    /// chain's native coin before it can be added. Enforced by the caller *after*
    /// `fetchInfo` returns (where `@Model` access is safe), so this is a vault-policy
    /// gate rather than part of "is this a real token" resolution. Defaults to `false`.
    var requiresVaultNativeCoin: Bool { get }
}

extension CustomTokenResolver {
    var requiresVaultNativeCoin: Bool { false }
}

/// Builds the `CustomTokenResolver` for a chain, mirroring the dispatch order of the
/// custom-token search: THORChain and Cardano are matched by chain, Terra/Terra
/// Classic share the CW20 seam, Solana has its own SPL lookup, and every other chain
/// falls through to the shared EVM/Tron/TON metadata lookup.
enum CustomTokenResolverFactory {
    /// - Parameter chain: The chain the custom-token screen is scoped to.
    static func make(chain: Chain) -> CustomTokenResolver {
        if chain == .thorChain {
            return ThorchainCustomTokenResolverStrategy()
        } else if chain == .cardano {
            return CardanoCustomTokenResolverStrategy(chain: chain)
        } else if chain == .terra || chain == .terraClassic {
            return Cw20CustomTokenResolverStrategy(chain: chain)
        } else if chain.chainType == .Solana {
            return SolanaCustomTokenResolverStrategy(chain: chain)
        } else if chain == .ripple {
            return RippleCustomTokenResolverStrategy()
        } else {
            return EvmLikeCustomTokenResolverStrategy(chain: chain)
        }
    }
}

// MARK: - Ripple

/// XRPL issued currencies are keyed by a `(currency, issuer)` **pair**, written as
/// the composite `<currency>.<issuer>` token id, so the shared
/// `AddressService.validateAddress` cannot judge the input — only its issuer half is
/// an address. Delegates to the shared ``RippleCustomTokenResolver``.
///
/// Unlike every other strategy here, this one performs **no network call**: XRPL has
/// no on-ledger token metadata registry, so a well-formed pair cannot be confirmed
/// to name a real, reputable token — only to be well-formed — and ticker/decimals
/// come from the identifier itself.
///
/// `requiresVaultNativeCoin` is `true` because a trust line costs an owner reserve
/// on the XRP account that holds it, so the vault must already hold XRP.
private struct RippleCustomTokenResolverStrategy: CustomTokenResolver {
    var requiresVaultNativeCoin: Bool { RippleCustomTokenResolver.requiresVaultNativeCoin }

    /// Throws only for input `validate` would already have rejected — the caller
    /// gates on `isValidAddress` first — so the throw is a guard against a future
    /// caller skipping validation, not an expected path.
    ///
    /// `async` is required by the protocol, not by this implementation: resolution
    /// is pure normalization with nothing to await, which is the whole point of the
    /// XRPL seam.
    func fetchInfo(contract: String) async throws -> CoinMeta? { // swiftlint:disable:this async_without_await
        try RippleCustomTokenResolver.resolve(input: contract)
    }

    func validate(_ address: String) -> Bool {
        RippleCustomTokenResolver.isValidInput(address)
    }
}

// MARK: - THORChain

/// THORChain non-RUNE tokens are Cosmos bank denoms referenced in `THOR.{SYMBOL}`
/// notation, not `thor1…` account addresses; delegates to the shared
/// ``ThorchainCustomTokenResolver``.
private struct ThorchainCustomTokenResolverStrategy: CustomTokenResolver {
    func fetchInfo(contract: String) async throws -> CoinMeta? {
        try await ThorchainCustomTokenResolver.resolve(input: contract)
    }

    func validate(_ address: String) -> Bool {
        ThorchainCustomTokenResolver.isValidInput(address)
    }
}

// MARK: - Cardano

/// Cardano native tokens are identified by a `policy_id.asset_name` hex asset id and
/// resolved via the native-tokens metadata service; a curated ``TokensStore`` entry
/// is preferred so known assets keep their ticker, logo, and `priceProviderId`.
private struct CardanoCustomTokenResolverStrategy: CustomTokenResolver {
    let chain: Chain

    func fetchInfo(contract: String) async throws -> CoinMeta? {
        let normalisedId = contract.lowercased()
        let metadata: CardanoTokenMetadata
        do {
            metadata = try await CardanoNativeTokensService.shared.resolveMetadata(assetId: normalisedId)
        } catch CardanoNativeTokensServiceError.assetNotFound {
            return nil
        }
        // Prefer the built-in registry entry when we know the asset — gives us the
        // curated ticker, logo, and `priceProviderId` (`USDM` instead of the `_USDM`
        // masked from the CIP-67 prefix, `usdm-2` instead of the empty default).
        return TokensStore.findTokenMeta(chain: chain, contractAddress: metadata.assetId)
            ?? CoinMeta(
                chain: chain,
                ticker: metadata.ticker,
                logo: metadata.registryLogo ?? .empty,
                decimals: metadata.decimals,
                priceProviderId: .empty,
                contractAddress: metadata.assetId,
                isNativeToken: false
            )
    }

    func validate(_ address: String) -> Bool {
        (try? CardanoAssetId.parse(address)) != nil
    }
}

// MARK: - Cosmos CW20 (Terra / Terra Classic)

/// Terra and Terra Classic CW20 tokens are CosmWasm contracts resolved via the
/// `{"token_info":{}}` smart query; delegates to the shared ``Cw20CustomTokenResolver``.
private struct Cw20CustomTokenResolverStrategy: CustomTokenResolver {
    let chain: Chain

    func fetchInfo(contract: String) async throws -> CoinMeta? {
        try await Cw20CustomTokenResolver.resolve(contractAddress: contract, chain: chain)
    }

    func validate(_ address: String) -> Bool {
        // CW20 contract addresses are not account addresses (Terra 2 contracts carry
        // 32-byte payloads, and 20-byte Terra Classic contracts are shape-identical to
        // wallets), so validate the bech32 contract shape instead of a send/receive
        // address.
        Cw20CustomTokenResolver.isValidInput(address, chain: chain)
    }
}

// MARK: - Solana

/// Solana SPL tokens are resolved through Jupiter's token-info endpoint; a match is
/// the entry whose `contractAddress` equals the queried mint.
private struct SolanaCustomTokenResolverStrategy: CustomTokenResolver {
    let chain: Chain

    func fetchInfo(contract: String) async throws -> CoinMeta? {
        let tokenInfos = try await SolanaService.shared.fetchTokensInfos(for: [contract])
        return tokenInfos.first(where: { $0.contractAddress == contract })
    }

    func validate(_ address: String) -> Bool {
        AddressService.validateAddress(address: address, chain: chain)
    }
}

// MARK: - EVM / Tron / TON

/// EVM, Tron, and TON share the same `(name, symbol, decimals)` lookup pattern. A
/// token resolves only when the metadata is complete; any other chain type or
/// incomplete metadata is not-found. The vault-must-hold-the-native-coin gate is
/// enforced by the caller after resolution (see ``requiresVaultNativeCoin``).
private struct EvmLikeCustomTokenResolverStrategy: CustomTokenResolver {
    let chain: Chain

    var requiresVaultNativeCoin: Bool { true }

    func fetchInfo(contract: String) async throws -> CoinMeta? {
        let tokenInfo: (name: String, symbol: String, decimals: Int)

        switch chain.chainType {
        case .EVM:
            let service = try EvmService.getService(forChain: chain)
            tokenInfo = try await service.getTokenInfo(contractAddress: contract)
        case .Tron:
            tokenInfo = try await TronService.shared.getTokenInfo(contractAddress: contract)
        case .Ton:
            tokenInfo = try await TonService.shared.getTokenInfo(contractAddress: contract)
        default:
            return nil
        }

        let (name, symbol, decimals) = tokenInfo

        guard !name.isEmpty, !symbol.isEmpty, decimals > 0 else {
            return nil
        }

        return CoinMeta(
            chain: chain,
            ticker: symbol,
            logo: .empty,
            decimals: decimals,
            priceProviderId: .empty,
            contractAddress: contract,
            isNativeToken: false
        )
    }

    func validate(_ address: String) -> Bool {
        AddressService.validateAddress(address: address, chain: chain)
    }
}
