//
//  BlockChainServiceProtocol.swift
//  VultisigApp
//
//  Test seam over `BlockChainService` for swap chain-specific fetches. Lets
//  the §2 SwapInteractor mock chain-specific fetches without touching the
//  network singleton.
//

import Foundation

protocol BlockChainServiceProtocol {
    func fetchSwapBlockChainSpecific(draft: SwapDraft) async throws -> BlockChainSpecific
}

extension BlockChainService: BlockChainServiceProtocol {
    func fetchSwapBlockChainSpecific(draft: SwapDraft) async throws -> BlockChainSpecific {
        try await fetchSpecific(swapDraft: draft)
    }
}
