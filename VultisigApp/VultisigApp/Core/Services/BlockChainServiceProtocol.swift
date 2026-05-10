//
//  BlockChainServiceProtocol.swift
//  VultisigApp
//
//  Test seam over `BlockChainService` for swap chain-specific fetches. Lets
//  the SwapInteractor mock chain-specific fetches without touching the
//  network singleton.
//

import Foundation

protocol BlockChainServiceProtocol {
    func fetchSwapBlockChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific
}

extension BlockChainService: BlockChainServiceProtocol {}
