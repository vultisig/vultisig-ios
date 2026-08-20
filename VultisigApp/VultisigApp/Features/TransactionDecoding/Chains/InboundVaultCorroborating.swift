//
//  InboundVaultCorroborating.swift
//  VultisigApp
//
//  Whether a signed destination is somewhere THORChain actually receives.
//

import Foundation

protocol InboundVaultCorroborating {

    /// Checks signed destination and chain against THORChain's inbound set.
    func corroborates(destination: String, chain: Chain, isNative: Bool) -> Bool
}

struct ThorchainInboundVaults: InboundVaultCorroborating {

    func corroborates(destination: String, chain: Chain, isNative: Bool) -> Bool {
        guard !destination.isEmpty,
              let known = ThorchainService.shared.cachedInboundAddresses()
        else { return false }

        // Only this transaction's chain can corroborate its route.
        let candidates = known.filter { $0.chain.caseInsensitiveCompare(chain.swapAsset) == .orderedSame }
        guard !candidates.isEmpty else { return false }

        return candidates.contains { entry in
            // Native deposits use the vault; tokens use the router.
            let expected = isNative ? entry.address : (entry.router ?? "")
            return !expected.isEmpty && Self.sameAddress(expected, destination, on: chain)
        }
    }

    /// EVM addresses are case-insensitive; other address families are not.
    private static func sameAddress(_ lhs: String, _ rhs: String, on chain: Chain) -> Bool {
        chain.chainType == .EVM
            ? lhs.caseInsensitiveCompare(rhs) == .orderedSame
            : lhs == rhs
    }
}
