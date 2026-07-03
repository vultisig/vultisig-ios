//
//  Cw20CustomTokenResolver.swift
//  VultisigApp
//

import Foundation

/// Resolves a user-pasted CW20 contract address into a ``CoinMeta`` for the
/// custom-token flow on Terra and Terra Classic.
///
/// CW20 tokens are CosmWasm contracts, not bank denoms, so their metadata
/// comes from the `{"token_info":{}}` smart query (via
/// ``CosmosTokenMetadataResolver/cw20TokenInfo(chain:contractAddress:)``)
/// rather than `denoms_metadata`. Input validation is a bech32 *shape* check
/// mirroring the SDK's `isCosmosWasmTokenId`: contract addresses can be
/// 20-byte (Terra Classic pre-migration contracts, indistinguishable from
/// wallet addresses) or 32-byte, so only the LCD query itself can tell a
/// contract from a wallet — a plausible-but-wrong address resolves to
/// not-found, never to a bogus token.
enum Cw20CustomTokenResolver {

    /// Bech32 prefix expected for CW20 contract addresses on this chain, or
    /// `nil` when the chain has no CW20 custom-token support.
    static func contractAddressPrefix(for chain: Chain) -> String? {
        switch chain {
        case .terra, .terraClassic:
            return "terra1"
        default:
            return nil
        }
    }

    /// Validates that the input is plausibly a CW20 contract address for the
    /// given chain, without hitting the network. Mirrors the SDK's
    /// `isCosmosWasmTokenId` shape (`prefix` + 20–80 lowercase-alphanumeric
    /// characters); `ibc/…` and `factory/…` denoms are bank denoms, not
    /// contracts, and are rejected.
    static func isValidInput(_ input: String, chain: Chain) -> Bool {
        guard let prefix = contractAddressPrefix(for: chain),
              input.hasPrefix(prefix) else {
            return false
        }
        let payload = input.dropFirst(prefix.count)
        guard (20...80).contains(payload.count) else {
            return false
        }
        return payload.allSatisfy { character in
            character.isASCII && ((character.isLetter && character.isLowercase) || character.isNumber)
        }
    }

    /// Resolves a CW20 contract address to a ``CoinMeta`` via the
    /// `token_info` smart query on the chain's LCD. A curated ``TokensStore``
    /// entry (matched by contract address) is preferred so known tokens keep
    /// their real logo and `priceProviderId`; unknown tokens get an empty
    /// logo and no price id — the same behavior as custom tokens on every
    /// other chain.
    ///
    /// - Returns: The resolved `CoinMeta`, or `nil` when the address is
    ///   definitively not a CW20 token (wallet address, non-CW20 contract,
    ///   unknown address).
    /// - Throws: Transport failures (rate limiting, network errors) from the
    ///   metadata lookup, so the caller can distinguish "try again later"
    ///   from "token not found".
    static func resolve(
        contractAddress: String,
        chain: Chain,
        metadataResolver: CosmosTokenMetadataResolver = .shared
    ) async throws -> CoinMeta? {
        guard isValidInput(contractAddress, chain: chain) else {
            return nil
        }

        guard let info = try await metadataResolver.cw20TokenInfo(
            chain: chain,
            contractAddress: contractAddress
        ) else {
            return nil
        }

        return TokensStore.findTokenMeta(chain: chain, contractAddress: contractAddress)
            ?? CoinMeta(
                chain: chain,
                ticker: info.symbol,
                logo: .empty,
                decimals: info.decimals,
                priceProviderId: .empty,
                contractAddress: contractAddress,
                isNativeToken: false
            )
    }
}
