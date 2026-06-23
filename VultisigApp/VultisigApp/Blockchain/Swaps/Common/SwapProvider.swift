//
//  SwapProvider.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 24.06.2024.
//

import Foundation

enum SwapProvider: Equatable {
    case thorchain
    case thorchainChainnet
    case thorchainStagenet
    case mayachain
    case oneinch(Chain)
    case kyberswap(Chain)
    case lifi
    case swapkit

    var streamingInterval: Int {
        switch self {
        case .mayachain:
            return 3
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return 0
        default:
            return 0
        }
    }

    /// Whether this provider can deliver the swapped funds to an external
    /// recipient AND we can verify, on-device before signing, that the built
    /// artifact actually targets that recipient.
    ///
    /// - THORChain/Maya: the recipient becomes the swap memo's `DESTADDR`
    ///   (`SwapService.fetchCrossChainQuote`). The node bakes it into the
    ///   returned `memo`, which is signed verbatim — so we can assert the memo
    ///   contains the recipient (`SwapRecipientVerifier`).
    /// - SwapKit: the recipient is passed as `/v3/swap` `destinationAddress`
    ///   and echoed back in the response, and every address is AML-screened
    ///   server-side. We assert the echoed `destinationAddress` equals the
    ///   recipient before signing, and surface AML refusals as recipient errors.
    ///
    /// The pure-aggregator routes (1inch / KyberSwap / LI.FI) bury the recipient
    /// inside opaque router calldata (`tx.data`) and return no structured echo
    /// of it (`tx.to` is the router, not the recipient). We therefore cannot
    /// satisfy the mandatory on-device output-target verification for them, so
    /// they stay excluded whenever an external recipient is set — picking one
    /// would either send funds to self (if the param were dropped) or land them
    /// somewhere we can't prove before signing. This is a verification
    /// constraint, not an API limitation: each of these providers does expose a
    /// recipient field (1inch `receiver`, KyberSwap `recipient`, LI.FI
    /// `toAddress`); enabling them safely needs a router-calldata decoder that
    /// recovers the on-chain output target, which does not exist yet.
    var honorsExternalRecipient: Bool {
        switch self {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain, .swapkit:
            return true
        case .oneinch, .kyberswap, .lifi:
            return false
        }
    }
}
