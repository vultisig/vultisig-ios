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

    /// Applies the SwapKit feature flag + the debug forced-provider gate to a
    /// raw natural-provider list.
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
        case ("jupiter", .jupiter):
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

    /// The natural swap-provider list for a coin's chain, before the SwapKit
    /// feature flag + forced-provider gates (`applyProviderGates`).
    ///
    /// THORChain / MayaChain are offered at the **chain** level — every token on
    /// a supported EVM chain carries the native provider, and the live quote
    /// decides the actual route: a real `Available` pool quotes through, anything
    /// else loses to an aggregator or surfaces `routeUnavailable`. There is no
    /// per-token allowlist here; token-level pool availability surfaces in the
    /// picker via the native-pool `DestinationTokenProvider`s.
    private var naturalSwapProviders: [SwapProvider] {
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
            return [.thorchain, .mayachain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
        case .bscChain:
            return [.thorchain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
        case .avalanche:
            return [.thorchain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
        case .arbitrum:
            return [.mayachain, .oneinch(chain), .lifi, .kyberswap(chain), .swapkit]
        case .base:
            return [.thorchain, .oneinch(chain), .lifi, .swapkit] // KyberSwap not supported
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
            // `.swapkit` enables EVM↔Solana / Solana↔EVM via NEAR Intents /
            // Chainflip; `.jupiter` serves on-Solana token swaps (SOL↔SPL,
            // SPL↔SPL). Jupiter is Solana-only and same-chain — cross-chain
            // pairs drop it automatically via the `SwapCoinsResolver` from∩to
            // intersection, and THORChain stays for SPL↔other-chain routes.
            return [.thorchain, .jupiter, .lifi, .swapkit]
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
        case .EVM, .Solana:
            // LI.FI now honours the `integrator`/`fee` params on Solana routes,
            // so Solana swaps charge the same VULT-discounted affiliate fee as
            // EVM. They were previously excluded because LI.FI rejected those
            // params on Solana, which left Solana routes uncharged while the UI
            // still displayed a fee — a display/charge mismatch.
            return true
        default:
            return false
        }
    }
}
