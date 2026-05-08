//
//  BlockChainServiceProtocol.swift
//  VultisigApp
//
//  Test seam over `BlockChainService.fetchSpecific(tx:)`. The protocol surface
//  takes a `SwapDraft` directly so post-§5 code paths don't reference the
//  legacy class. Today's concrete bridges through a temp `SwapTransaction` —
//  removed in §5 once the underlying body is rewritten to read drafts.
//

import Foundation

protocol BlockChainServiceProtocol {
    func fetchSwapBlockChainSpecific(draft: SwapDraft) async throws -> BlockChainSpecific
}

extension BlockChainService: BlockChainServiceProtocol {
    func fetchSwapBlockChainSpecific(draft: SwapDraft) async throws -> BlockChainSpecific {
        let tx = SwapTransaction()
        draft.apply(to: tx)
        return try await fetchSpecific(tx: tx)
    }
}
