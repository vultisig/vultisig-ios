//
//  SwapHaltGate.swift
//  VultisigApp
//
//  Shared halt resolution for THORChain / MayaChain `/inbound_addresses`. A
//  chain is halted when its inbound entry reports `halted`, `global_trading_paused`,
//  or `chain_trading_paused`. Used by the screen-level dim (SwapDetailsViewModel)
//  and the sign-time pre-flight block (SwapVerifyScreen).
//

import Foundation

enum SwapHaltGate {

    /// True when the chain's inbound entry signals a halt. Returns `false` when
    /// the chain is absent from the inbound list — a chain with no inbound entry
    /// is not a native-protocol route, so there's nothing to halt here.
    static func isHalted(chain: Chain, in inbound: [InboundAddress]) -> Bool {
        let chainName = ThorchainService.getInboundChainName(for: chain)
        guard let entry = inbound.first(where: { $0.chain.caseInsensitiveCompare(chainName) == .orderedSame }) else {
            return false
        }
        return entry.halted || entry.global_trading_paused || entry.chain_trading_paused
    }

    /// The set of chains (from the supplied universe) that are halted under the
    /// given inbound snapshots. Both protocols' inbound lists are unioned.
    static func haltedChains(
        among chains: Set<Chain>,
        thorInbound: [InboundAddress],
        mayaInbound: [InboundAddress]
    ) -> Set<Chain> {
        chains.filter { chain in
            isHalted(chain: chain, in: thorInbound) || isHalted(chain: chain, in: mayaInbound)
        }
    }
}
