//
//  SwapKitCapability.swift
//  VultisigApp
//

enum SwapKitCapability {
    /// The app can hold a destination asset on these chains. Exact token
    /// support is still decided by the live SwapKit catalogue.
    static func canReceive(on chain: Chain) -> Bool {
        if chain.chainType == .EVM {
            return chain.isSwapAvailable
        }

        switch chain {
        case .bitcoin,
             .bitcoinCash,
             .cardano,
             .dash,
             .dogecoin,
             .litecoin,
             .ripple,
             .solana,
             .sui,
             .ton,
             .tron,
             .zcash:
            return true
        default:
            return false
        }
    }

    /// Source-side eligibility is directional. EVM SwapKit transactions must
    /// be reputation-checked before signing, so only networks with a known
    /// Blockaid identifier can originate a route. This deliberately keeps
    /// Robinhood destination-only until Blockaid supports chain 4663.
    static func canQuote(from chain: Chain) -> Bool {
        guard canReceive(on: chain) else { return false }
        if chain.chainType == .EVM {
            return BlockaidChainIdentifier.name(for: chain) != nil
        }
        return true
    }
}
