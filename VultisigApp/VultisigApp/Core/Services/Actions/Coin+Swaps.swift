//
//  Coin+Swaps.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 11.06.2024.
//

import Foundation

extension Coin {

    var thorswapMultiplier: Decimal {
        switch chain {
        case .mayaChain:
            return pow(10, decimals)
        default:
            return 1e8
        }
    }

    var isSwapSupported: Bool {
        return !swapProviders.isEmpty
    }

    var swapProviders: [SwapProvider] {
        // SwapKit is opt-in behind the Settings → Advanced → "SwapKit"
        // toggle. When the flag is off, drop `.swapkit` from every chain's
        // provider list — ranking falls back to the other providers exactly
        // as before the SwapKit integration shipped. Single point of
        // gating: every chain's switch arm below carries `.swapkit` as if
        // unconditionally enabled, and this filter prunes when needed.
        return applyProviderGates(naturalSwapProviders)
    }

    /// Dynamic variant of `swapProviders` for the swap-screen load path: the EVM
    /// native (THORChain / MayaChain) eligibility is the UNION of the live
    /// `Available` pools and the static fallback, rather than the static arrays
    /// alone. A fetch can only ADD native routes. `nil` snapshots (cold start /
    /// fetch failure) fall back to the static set, so the result is never worse
    /// than `swapProviders`.
    func swapProviders(thorPools: [NativePoolAsset]?, mayaPools: [NativePoolAsset]?) -> [SwapProvider] {
        applyProviderGates(naturalSwapProviders(eligibleNative: eligibleNative(thorPools: thorPools, mayaPools: mayaPools)))
    }

    /// The native eligibility used by the swap-screen picker: static fallback
    /// OR a live `Available` pool match (UNION). EVM-only; the per-chain arms in
    /// `naturalSwapProviders(eligibleNative:)` decide whether either flag is read.
    func eligibleNative(thorPools: [NativePoolAsset]?, mayaPools: [NativePoolAsset]?) -> NativeEligibility {
        var eligible = staticEligibleNativeProviders
        if let thorPools,
           NativePoolEligibility.isEligible(chain: chain, ticker: ticker, contract: contractAddress, in: thorPools) {
            eligible.thorchain = true
        }
        if let mayaPools,
           NativePoolEligibility.isEligible(chain: chain, ticker: ticker, contract: contractAddress, in: mayaPools) {
            eligible.mayachain = true
        }
        return eligible
    }

    /// Applies the SwapKit feature flag + the debug forced-provider gate to a
    /// raw natural-provider list. Shared by the static and dynamic paths so both
    /// honor the same opt-in / forced-pin behaviour.
    private func applyProviderGates(_ raw: [SwapProvider]) -> [SwapProvider] {
        // SwapKit is opt-in behind the Settings → Advanced → "SwapKit" toggle.
        let afterSwapKitGate = SwapKitConfig.isFeatureEnabled
            ? raw
            : raw.filter { $0 != .swapkit }

        // Debug-only: Settings → Advanced → "Force swap provider" lets a
        // tester pin every quote to a single provider so the chosen
        // signing path is exercised in isolation (ranking ties don't
        // matter). Empty UserDefaults value = no force = production
        // ranking across all providers. The forced-provider gate runs
        // AFTER the SwapKit feature flag — if SwapKit is off and the
        // forced provider is "swapkit", the result is empty and the swap
        // UI surfaces "no providers available" rather than silently
        // re-enabling SwapKit.
        let forced = UserDefaults.standard.string(forKey: "forcedSwapProvider") ?? ""
        guard !forced.isEmpty else { return afterSwapKitGate }
        return afterSwapKitGate.filter { matchesForcedProvider($0, forced: forced) }
    }

    private func matchesForcedProvider(_ provider: SwapProvider, forced: String) -> Bool {
        switch (forced, provider) {
        case ("swapkit", .swapkit):
            return true
        case ("oneInch", .oneinch):
            return true
        case ("kyberSwap", .kyberswap):
            return true
        case ("lifi", .lifi):
            return true
        case ("thorchain", .thorchain),
             ("thorchain", .thorchainChainnet),
             ("thorchain", .thorchainStagenet):
            return true
        case ("mayachain", .mayachain):
            return true
        default:
            return false
        }
    }

    /// Whether the native protocols gate a coin for swaps. EVM tokens are gated
    /// (THORChain / MayaChain pools); everything else is decided per chain arm.
    struct NativeEligibility {
        var thorchain: Bool
        var mayachain: Bool
    }

    private var naturalSwapProviders: [SwapProvider] {
        // Cold-start / sync default: the static ticker arrays. The swap-screen
        // load path supersedes this by UNION with live `Available` pools (see
        // `eligibleNativeSwapProviders`); a fetch can only ADD native routes.
        return naturalSwapProviders(eligibleNative: staticEligibleNativeProviders)
    }

    /// The native (THORChain / MayaChain) providers a coin is eligible for under
    /// the static fallback arrays. EVM-only; non-EVM chains don't consult it.
    private var staticEligibleNativeProviders: NativeEligibility {
        var eligible = NativeEligibility(thorchain: false, mayachain: false)
        switch chain {
        case .ethereum:
            eligible.thorchain = thorEthTokens.contains(ticker)
            eligible.mayachain = mayaEthTokens.contains(ticker)
        case .bscChain:
            eligible.thorchain = thorBscTokens.contains(ticker)
        case .avalanche:
            eligible.thorchain = thorAvaxTokens.contains(ticker)
        case .arbitrum:
            eligible.mayachain = mayaArbTokens.contains(ticker)
        case .base:
            eligible.thorchain = thorBaseTokens.contains(ticker)
        default:
            break
        }
        return eligible
    }

    /// The full provider list given a precomputed eligible-native set. The EVM
    /// arms read `eligibleNative` instead of the static arrays so the swap-screen
    /// load path can pass in the UNION of fetched-`Available` pools + the
    /// fallback. Non-EVM arms are unchanged (not array-gated).
    private func naturalSwapProviders(eligibleNative: NativeEligibility) -> [SwapProvider] {
        switch chain {
        case .mayaChain, .kujira:
            return [.mayachain]
        case .dash:
            // Tier 1 L1 source — `.swapkit` enables DASH↔EVM / DASH↔SOL routes
            // via NEAR Intents. Wire shape mirrors DOGE (legacy P2PKH PSBT,
            // no segwit); signed through `SwapKitDashSigner` riding
            // WalletCore's `CoinType.dash` end-to-end. MayaChain stays as
            // a provider — both rank against each other per quote.
            return [.mayachain, .swapkit]
        case .ethereum:
            let defaultProviders: [SwapProvider] = [
                .oneinch(chain),
                .lifi,
                .kyberswap(chain),
                .swapkit
            ]

            var providers: [SwapProvider] = []

            if eligibleNative.thorchain {
                providers.append(.thorchain)
            }

            if eligibleNative.mayachain {
                providers.append(.mayachain)
            }

            return providers + defaultProviders
        case .bscChain:
            if eligibleNative.thorchain {
                return [.thorchain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            } else {
                return [.oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            }
        case .avalanche:
            if eligibleNative.thorchain {
                return [.thorchain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            } else {
                return [.oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            }
        case .arbitrum:
            if eligibleNative.mayachain {
                return [.mayachain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            } else {
                return [.oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
            }
        case .base:
            if eligibleNative.thorchain {
                return [.thorchain, .oneinch(chain), .lifi, .swapkit] // KyberSwap not supported
            }
            return [.oneinch(chain), .lifi, .swapkit] // KyberSwap not supported
        case .optimism, .polygon, .polygonV2:
            return [.lifi, .oneinch(chain), .kyberswap(chain), .swapkit] // KyberSwap supported
        case .mantle:
            // `.swapkit` is included unconditionally — eligibility per chain
            // is gated dynamically by `SwapKitProviderCache.isEnabled`
            // against the cached `/v3/providers.enabledChainIds`. If
            // SwapKit lights up Mantle later, no iOS release needed.
            return [.lifi, .oneinch(chain), .kyberswap(chain), .swapkit]
        case .zksync:
            return [.oneinch(chain), .lifi, .swapkit] // KyberSwap not supported on zkSync
        case .blast:
            return [.lifi, .swapkit] // KyberSwap not supported on Blast
        case .thorChain:
            return [.thorchain, .mayachain]
        case .thorChainChainnet:
            return [.thorchainChainnet]
        case .thorChainStagenet:
            return [.thorchainStagenet]
        case .bitcoin:
            // Phase 2 chain — `.swapkit` enables BTC↔EVM / BTC↔SOL / BTC↔TON
            // / BTC↔SUI / BTC↔ADA routes via NEAR Intents / Chainflip /
            // Garden / Flashnet / Harbor. SwapKit returns a pre-built base64
            // PSBT and we sign it through the same UTXO helper path
            // THORChain BTC swaps already use.
            return [.thorchain, .mayachain, .swapkit]
        case .dogecoin:
            // Tier 1 L1 source — `.swapkit` enables DOGE↔EVM / DOGE↔SOL routes
            // via NEAR Intents. Wire shape matches BTC (`meta.txType: "PSBT"`)
            // but inputs are legacy P2PKH; signed through `SwapKitDogeSigner`
            // riding WalletCore's `CoinType.dogecoin` end-to-end.
            return [.thorchain, .swapkit]
        case .bitcoinCash:
            // Tier 1 L1 source — same shape as DOGE (legacy P2PKH PSBT).
            // BCH adds SIGHASH_FORKID natively via WalletCore.
            return [.thorchain, .swapkit]
        case .litecoin:
            // Tier 1 L1 source — flag-flip-ready. LTC reuses the existing
            // `SwapKitBTCSigner` (segwit-compatible — LTC addresses are
            // P2WPKH / P2SH-P2WPKH). No-op today because
            // `SwapKitProviderCache.chainEnabled(.litecoin)` returns false
            // until upstream lists `"litecoin"` in `/v3/providers.enabledChainIds`.
            // Despite this, `/v3/quote` serves LTC routes via NEAR — the gate
            // is overly conservative. Shipping the flip pre-emptively so the
            // gate flip is the only diff when upstream lights up.
            return [.thorchain, .swapkit]
        case .gaiaChain:
            return [.thorchain]
        case .solana:
            // Phase 1 chain — `.swapkit` enables EVM↔Solana and Solana↔EVM
            // routes via NEAR Intents / Chainflip / etc.
            return [.thorchain, .lifi, .swapkit]
        case .hyperliquid:
            return [.lifi]
        case .cronosChain:
            return [.lifi]
        case .zcash:
            // Tier 1 L1 source — `.swapkit` enables ZEC↔EVM / ZEC↔SOL routes
            // via NEAR Intents. Transparent-only by hard MPC constraint
            // (Vultisig can't manage shielded keys). Sapling-v4 PSBT signed
            // through `SwapKitZcashSigner` with ZIP-243 sighash via
            // WalletCore `CoinType.zcash`.
            return [.mayachain, .swapkit]
        case .ripple:
            // Tier 1 L1 source — `.swapkit` enables XRP↔EVM / XRP↔SOL routes
            // via NEAR Intents. Deposit-only flow: SwapKit returns a per-route
            // NEAR-allocated r-address and Vultisig builds a plain Payment
            // through the existing `RippleHelper`. Destination-tag plumbing
            // is defensive — NEAR's ephemeral deposit pattern doesn't need
            // tags, but a future Chainflip shared-vault flip would silently
            // misroute funds without it.
            return [.thorchain, .swapkit]
        case .tron:
            return [.thorchain, .swapkit]
        case .ton, .cardano, .sui:
            return [.swapkit]
        case .polkadot, .dydx, .osmosis, .terra, .terraClassic, .noble, .akash, .ethereumSepolia, .sei, .qbtc, .bittensor:
            return []
        }
    }

    var isLifiFeesSupported: Bool {
        switch chain.chainType {
        case .EVM:
            return true
        default:
            return false
        }
    }
}

private extension Coin {

    var mayaEthTokens: [String] {
        return ["ETH", "USDC"]
    }

    var mayaArbTokens: [String] {
        return ["ETH", "ARB", "USDC", "YUM", "TGT", "GLD", "USDT", "PEPE"]
    }

    var thorEthTokens: [String] {
        return ["ETH", "USDT", "USDC", "WBTC", "THOR", "XRUNE", "DAI", "LUSD", "GUSD", "VTHOR", "USDP", "LINK", "WSTETH", "TGT", "AAVE", "FOX", "DPI", "SNX", "vTHOR"]
    }

    var thorBscTokens: [String] {
        return ["BNB", "USDT", "USDC"]
    }

    var thorBaseTokens: [String] {
        return ["ETH", "USDC", "CBBTC"]
    }

    var thorAvaxTokens: [String] {
        return ["AVAX", "USDC", "USDT", "SOL"]
    }
}
