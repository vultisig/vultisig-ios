//
//  ChainPoller.swift
//  VultisigApp
//
//  `DoneStatusPoller` backed by `TransactionStatusViewModel`'s
//  per-chain RPC poller. Used by Send / QBTC / non-SwapKit swap (both
//  initiator and cosigner) and by the cosigner Send branch.
//

import Foundation
import SwiftUI

@MainActor
final class ChainPoller: DoneStatusPoller {
    let initialStatus: TransactionStatus

    private let viewModel: TransactionStatusViewModel
    private var observationTask: Task<Void, Never>?

    init(
        txHash: String,
        chain: Chain,
        coinTicker: String?,
        amount: String?,
        toAddress: String?,
        pubKeyECDSA: String?
    ) {
        let viewModel = TransactionStatusViewModel(
            txHash: txHash,
            chain: chain,
            coinTicker: coinTicker,
            amount: amount,
            toAddress: toAddress,
            pubKeyECDSA: pubKeyECDSA
        )
        self.viewModel = viewModel
        self.initialStatus = viewModel.status
    }

    func start(onStatus: @escaping (TransactionStatus) -> Void) {
        guard observationTask == nil else { return }
        viewModel.startPolling()
        observationTask = Task { [viewModel] in
            for await newStatus in viewModel.$status.values {
                onStatus(newStatus)
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        viewModel.stopPolling()
    }
}
