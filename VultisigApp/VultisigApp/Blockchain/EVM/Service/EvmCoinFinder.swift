//
//  EvmCoinFinder.swift
//  VultisigApp
//
//  Cross-platform-parity EVM token discovery.
//
//  Mirrors `vultisig-sdk/packages/core/chain/coin/find/resolvers/evm/index.ts`
//  byte-for-byte where it matters:
//  1. 1inch `/balance/v1.2/{chain}/balances/{address}` for the holdings map.
//  2. Drop tokens with zero balance + the native-coin sentinel.
//  3. 1inch `/token/v1.2/{chain}/custom?addresses=...` for metadata.
//  4. Keep only tokens with `logoURI && providers.contains("CoinGecko")` —
//     CoinGecko provenance is the legitimacy signal (allowlist), replacing
//     the old Alchemy-based `isSpamToken` empty-logo blocklist that was
//     dropping legit small-caps (see vultisig/vultisig-ios#4334).
//  5. Top up with VULT if the user holds it but 1inch didn't surface it
//     (Ethereum-only).
//

import BigInt
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "evm-coin-finder")

enum EvmCoinFinder {

    /// Chains for which 1inch publishes `/balance` + `/token` APIs. EVM chains
    /// outside this list have no 1inch surface; callers fall back to the
    /// TokensStore-iteration path.
    static let oneInchSupportedChains: Set<Chain> = [
        .ethereum,
        .base,
        .arbitrum,
        .polygon,
        .polygonV2,
        .optimism,
        .bscChain,
        .avalanche
    ]

    /// The "native coin" placeholder address that 1inch uses for the chain
    /// gas token (ETH/BNB/MATIC/etc.). We exclude it from the discovered set
    /// because the native coin is already represented as the chain's
    /// `isNativeToken` entry.
    static let nativeCoinSentinel = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    /// VULT contract on Ethereum. Used for the top-up at the end of discovery
    /// — `findEvmCoins` in the SDK does the same.
    private static let vultEthereumContract = "0xb788144df611029c60b859df47e79b7726c4deba"

    static func isSupported(chain: Chain) -> Bool {
        oneInchSupportedChains.contains(chain)
    }

    static func find(chain: Chain, address: String) async -> [CoinMeta] {
        guard isSupported(chain: chain), let chainId = chain.chainID else {
            return []
        }

        let balances: [String: String]
        do {
            balances = try await OneInchService.shared.fetchBalances(chain: chainId, address: address)
        } catch {
            logger.warning("1inch balance fetch failed for \(chain.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        // Step 1: filter to non-zero balances and drop the native-coin sentinel
        // (it shows up in 1inch's response for the gas token itself).
        let heldContracts = balances.compactMap { contract, balance -> String? in
            let normalised = contract.lowercased()
            guard normalised != nativeCoinSentinel else { return nil }
            guard let amount = BigInt(balance), amount > 0 else { return nil }
            return normalised
        }

        var discovered: [CoinMeta] = []

        if !heldContracts.isEmpty {
            let tokenInfo: [String: OneInchToken]
            do {
                tokenInfo = try await OneInchService.shared.fetchCustomTokens(
                    chain: chainId,
                    addresses: heldContracts
                )
            } catch {
                logger.warning("1inch token-info fetch failed for \(chain.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                tokenInfo = [:]
            }

            for contract in heldContracts {
                // 1inch's response keys are lowercase; the lookup table here
                // is the same shape so a direct hit works without
                // case-folding the key set.
                guard let token = tokenInfo[contract] else { continue }
                // Allowlist: legit tokens have a logoURI AND are tagged as
                // CoinGecko-known. This is the inverse of the old empty-logo
                // blocklist — keeps small-cap CoinGecko-listed tokens that
                // Alchemy doesn't curate, drops random airdrop dust that
                // CoinGecko hasn't listed.
                guard let logoURI = token.logoURI, !logoURI.isEmpty else { continue }
                guard token.isCoinGeckoVerified else { continue }

                // Prefer the curated TokensStore entry when we know the
                // contract: keeps the bundled logo asset + priceProviderId
                // instead of the 1inch CDN URL. Matches the same lookup we
                // do for Cardano CNT auto-discovery.
                if let known = TokensStore.findTokenMeta(chain: chain, contractAddress: contract) {
                    discovered.append(known)
                } else {
                    discovered.append(CoinMeta(
                        chain: chain,
                        ticker: token.symbol,
                        logo: logoURI,
                        decimals: token.decimals,
                        priceProviderId: .empty,
                        contractAddress: contract,
                        isNativeToken: false
                    ))
                }
            }
        }

        // Step 2: VULT top-up on Ethereum — if the address holds VULT but
        // 1inch didn't surface it, check directly via `eth_call`. Mirrors
        // the SDK's `findEvmCoins` final block.
        if chain == .ethereum {
            let hasVult = discovered.contains { $0.contractAddress.lowercased() == vultEthereumContract }
            if !hasVult, await balanceCheckErc20(chain: chain, contract: vultEthereumContract, holder: address) > 0,
               let vult = TokensStore.findTokenMeta(chain: .ethereum, contractAddress: vultEthereumContract) {
                discovered.append(vult)
            }
        }

        return discovered
    }

    /// Direct `eth_call balanceOf(holder)` against the chain's RPC. Returns
    /// 0 on any error so callers can use it in an `if > 0` filter without a
    /// dedicated do/catch.
    private static func balanceCheckErc20(chain: Chain, contract: String, holder: String) async -> BigInt {
        do {
            let service = try EvmService.getService(forChain: chain)
            return try await service.fetchERC20TokenBalance(contractAddress: contract, walletAddress: holder)
        } catch {
            return 0
        }
    }
}
