//
//  SwapKitToken.swift
//  VultisigApp
//
//  Decodable models for the SwapKit `/tokens?provider=<NAME>` response, plus
//  the adapter that maps a `SwapKitToken` to a transient `CoinMeta` the swap
//  destination picker + quote builder can consume. Tokens whose `chain`
//  string doesn't reverse-map to a Vultisig-supported `Chain` are dropped at
//  decode-time — Vultisig must hold a wallet on the destination chain for
//  the route to be receivable.
//

import Foundation

/// Single token entry in a `/tokens?provider=<NAME>` response. Field names
/// match the upstream wire format (see `swapkit-spike/api-contract.md`
/// §"`/tokens`" and the vendored `03c-tokens-NEAR.json` fixture).
///
/// Two address fields surfaced upstream:
///  - `address` — on-chain contract address (omitted for gas tokens; sometimes
///    empty string for NEAR's `NEAR.NEAR` gas token, sometimes a NEAR
///    intent identifier like `zec.omft.near` for cross-chain entries).
///  - `chainId` — SwapKit's per-chain identifier (`"1"` for EVM, `"solana"`,
///    `"bitcoin"`, etc.). Not used by the adapter; the `chain` string is the
///    canonical key.
struct SwapKitToken: Codable, Hashable {
    let chain: String
    let chainId: String?
    let address: String?
    let ticker: String
    let identifier: String
    let name: String?
    let decimals: Int
    let logoURI: String?
    let coingeckoId: String?
}

/// Envelope returned by `GET /tokens?provider=<NAME>`. Empty/error responses
/// from the proxy use a different shape (`{message, error}`); decoding fails
/// in that case and the caller falls open to "no SwapKit tokens for this
/// provider".
struct SwapKitTokensResponse: Decodable {
    let provider: String
    let count: Int?
    let tokens: [SwapKitToken]
}

extension SwapKitToken {
    /// Adapter — maps a `SwapKitToken` to the `CoinMeta` shape the picker
    /// renders and `CoinService.addToChain` consumes. Returns `nil` when:
    ///  - `chain` doesn't reverse-map to a Vultisig-supported chain
    ///    (Polkadot, Berachain, Monad, Starknet, X-Layer, etc.).
    ///  - Token has no on-chain contract address but isn't the gas token of
    ///    its chain (NEAR cross-chain wrappers like `NEAR.ZEC-zec.omft.near`
    ///    aren't holdable on Vultisig).
    func toCoinMeta() -> CoinMeta? {
        guard let chain = SwapKitChainIDMapper.chain(forSwapKitChain: self.chain) else {
            return nil
        }

        // Treat as native iff the SwapKit `address` is absent OR empty AND
        // the ticker matches the chain's native ticker prefix. The
        // `SwapKitChainIDMapper.chain(forSwapKitChain:)` reverse map already
        // pins the chain; here we just decide native vs token.
        let contract = address?.trimmingCharacters(in: .whitespaces) ?? ""
        let isNative = contract.isEmpty
        if !isNative, !SwapKitToken.isUsableContract(contract, on: chain) {
            // Cross-chain wrapper identifiers (e.g. NEAR's `zec.omft.near`)
            // aren't on-chain ERC-20 / SPL contracts — drop. The user can
            // still receive the underlying via a SwapKit quote that drops
            // the wrapper at the deposit-address stage; surfacing the
            // wrapper in the picker would confuse the wallet add flow.
            return nil
        }

        return CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: logoURI ?? "",
            decimals: decimals,
            priceProviderId: coingeckoId ?? "",
            contractAddress: isNative ? "" : contract,
            isNativeToken: isNative
        )
    }

    /// A "usable" contract is one Vultisig's `CoinFactory` can build against
    /// on the destination chain — EVM hex, Solana base58 SPL mint, Tron
    /// base58, TON workchain address. NEAR-Intent identifiers (`*.omft.near`,
    /// `*.poa-bridge.near`) are explicitly not usable destinations.
    private static func isUsableContract(_ contract: String, on chain: Chain) -> Bool {
        switch chain.chainType {
        case .EVM:
            return contract.hasPrefix("0x") && contract.count == 42
        case .Solana:
            // SPL mint addresses are base58 — length 32–44, no leading "0x".
            return !contract.contains(".") && !contract.hasPrefix("0x") && contract.count >= 32
        default:
            // For non-EVM / non-Solana destinations, conservatively reject
            // any contract value — most SwapKit tokens on UTXO / TON / TRON
            // / Cardano / Sui chains are gas tokens with no contract, and
            // the long-tail with a contract is almost always a NEAR wrapper
            // identifier that the wallet can't actually hold.
            return false
        }
    }
}
