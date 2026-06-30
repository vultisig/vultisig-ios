//
//  QBTCClaimCoinResolver.swift
//  VultisigApp
//
//  Resolves the Bitcoin and QBTC accounts a QBTC claim is derived from.
//  Neither chain has to be enabled in the vault: an already-enabled
//  native coin is used as-is, otherwise the account is derived in-memory
//  from the native-token template + the vault's own keys via the pure,
//  non-persisting `CoinFactory.create` (the same precedent
//  `SwapCryptoLogic.getDefaultCoin` uses). Nothing is appended to
//  `vault.coins` or written to storage — the resolved coins stay local
//  to the claim flow, so the deterministic claim hash is identical to
//  the one computed when the chains are enabled.
//
//  Bitcoin (ECDSA) derives for any standard vault; QBTC (MLDSA) requires
//  a non-empty `publicKeyMLDSA44`, so the only genuine failure is a
//  non-quantum vault — surfaced as `Error.derivationFailed`.
//

import Foundation

@MainActor
struct QBTCClaimCoinResolver {

    /// `nonisolated` so the resolver can be default-constructed as an
    /// initializer argument (default arguments are evaluated in a
    /// nonisolated context). The synthesized initializer can't be used —
    /// it would inherit `@MainActor` and fail as a default argument — so
    /// this explicit one is required despite looking redundant. The
    /// stateful work (the `@Model`-reading `resolve` methods) stays
    /// main-actor isolated.
    nonisolated init() {} // swiftlint:disable:this unneeded_synthesized_initializer

    enum Error: LocalizedError, Equatable {
        /// The native coin for `chainName` is neither enabled nor
        /// derivable from the vault's keys (e.g. a non-quantum vault has
        /// no MLDSA-44 key to derive the QBTC account).
        case derivationFailed(chainName: String)

        var errorDescription: String? {
            switch self {
            case .derivationFailed(let chainName):
                return String(format: "qbtcClaimMissingCoinDetail".localized, chainName)
            }
        }
    }

    /// The Bitcoin and QBTC accounts a QBTC claim is derived from.
    struct Coins: Equatable {
        let btc: Coin
        let qbtc: Coin
    }

    /// Resolves both accounts the claim needs. Throws on the first chain
    /// that can't be resolved.
    func resolve(vault: Vault) throws -> Coins {
        Coins(
            btc: try resolve(vault: vault, chain: .bitcoin),
            qbtc: try resolve(vault: vault, chain: .qbtc)
        )
    }

    /// Returns the enabled native coin for `chain` if present, otherwise
    /// derives it in-memory. Throws `Error.derivationFailed` only when the
    /// vault genuinely lacks the key material to derive the account.
    func resolve(vault: Vault, chain: Chain) throws -> Coin {
        if let enabled = vault.nativeCoin(for: chain) {
            return enabled
        }
        guard let meta = Self.nativeMeta(for: chain) else {
            throw Error.derivationFailed(chainName: chain.name)
        }
        let pubKey = vault.chainPublicKeys.first { $0.chain == chain }?.publicKeyHex
        do {
            return try CoinFactory.create(
                asset: meta,
                publicKeyECDSA: pubKey ?? vault.pubKeyECDSA,
                publicKeyEdDSA: pubKey ?? vault.pubKeyEdDSA,
                hexChainCode: vault.hexChainCode,
                isDerived: pubKey != nil,
                publicKeyMLDSA44: vault.publicKeyMLDSA44
            )
        } catch {
            throw Error.derivationFailed(chainName: chain.name)
        }
    }

    /// Native-token template for the chain. QBTC has a dedicated
    /// `TokensStore.qbtc`; Bitcoin (and any other chain) resolves its
    /// inline native entry from the asset list.
    private static func nativeMeta(for chain: Chain) -> CoinMeta? {
        if chain == .qbtc {
            return TokensStore.qbtc
        }
        return TokensStore.TokenSelectionAssets.first { $0.chain == chain && $0.isNativeToken }
    }
}
