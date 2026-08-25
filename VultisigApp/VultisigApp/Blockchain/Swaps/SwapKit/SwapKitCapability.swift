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

    /// The `/swap` payload must match the source chain's implemented signer.
    /// A typed payload for the wrong chain is as unsafe as an unknown payload:
    /// both are rejected before the quote can enter ranking.
    static func canSign(_ tx: SwapKitTx, from chain: Chain) -> Bool {
        switch (chain, tx) {
        case (_, .evm) where chain.chainType == .EVM:
            return true
        case (.solana, .solana),
             (.bitcoin, .psbt),
             (.litecoin, .psbt),
             (.dogecoin, .dogecoinPsbt),
             (.bitcoinCash, .bitcoinCashPsbt),
             (.dash, .dashPsbt),
             (.zcash, .zcashPsbt),
             (.ton, .ton),
             (.cardano, .cardano),
             (.cardano, .cardanoPrebuilt),
             (.sui, .sui),
             (.tron, .tron),
             (.ripple, .rippleDepositOnly):
            return true
        default:
            return false
        }
    }
}
