//
//  SecurityScanViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-07-29.
//

import Foundation
import Combine
import SwiftUI

enum SecurityScannerState: Equatable {
    case idle
    case scanning
    case scanned(SecurityScannerResult)
    case notScanned(provider: String)

    var shouldShowWarning: Bool {
        switch self {
        case .scanned(let result):
            return !result.isSecure
        case .scanning, .notScanned, .idle:
            return false
        }
    }

    var result: SecurityScannerResult? {
        switch self {
        case .scanned(let result):
            return result
        case .scanning, .notScanned, .idle:
            return nil
        }
    }
}

class SecurityScannerViewModel: ObservableObject {
    @Published var state = SecurityScannerState.idle

    private let service: SecurityScannerServiceProtocol

    init(service: SecurityScannerServiceProtocol = SecurityScannerServiceFactory.buildSecurityScannerService()) {
        self.service = service
    }

    func scan(transaction: SendTransaction) async {
        guard isScanningAvailable(for: transaction.coin.chain) else { return }
        await scan(transactionType: .send(transaction))
    }

    func scan(transaction: SwapTransaction) async {
        guard isScanningAvailable(for: transaction.fromCoin.chain) else {
            // The source-chain swap tx can't be scanned, but an external
            // recipient on a screenable destination chain still must be — fall
            // through to a recipient-only scan instead of returning unscanned.
            if transaction.hasExternalRecipient {
                await scanRecipientOnly(transaction: transaction)
            }
            return
        }
        await scan(transactionType: .swap(transaction))
    }

    private func scan(transactionType: SecurityScannerTransactionType) async {
        do {
            let tx: SecurityScannerTransaction
            switch transactionType {
            case .swap(let swapTransaction):
                tx = try await service.createSecurityScannerTransaction(transaction: swapTransaction)
            case .send(let sendTransaction):
                tx = try await service.createSecurityScannerTransaction(transaction: sendTransaction, vault: sendTransaction.vault)
            }
            await update(state: .scanning)

            var result = try await service.scanTransaction(tx)

            // Safety net (HIGH tier): when an external recipient is set, also
            // screen the recipient on the destination chain and keep the worse
            // of the two results so a flagged recipient blocks signing even if
            // the source-chain swap tx itself scans clean.
            if case let .swap(swapTransaction) = transactionType,
               swapTransaction.hasExternalRecipient,
               let recipientResult = await scanRecipient(transaction: swapTransaction) {
                result = Self.lessSecure(result, recipientResult)
            }

            await update(state: .scanned(result))
        } catch {
            if case let SecurityScannerError.notScanned(provider) = error {
                await update(state: .notScanned(provider: provider))
            } else {
                await update(state: .idle)
            }
        }
    }

    /// Recipient-only scan path, used when the source-chain swap tx itself
    /// isn't screenable but the external recipient's destination chain is.
    private func scanRecipientOnly(transaction: SwapTransaction) async {
        await update(state: .scanning)
        guard let result = await scanRecipient(transaction: transaction) else {
            await update(state: .idle)
            return
        }
        await update(state: .scanned(result))
    }

    /// Screen the external recipient on the destination chain. Returns `nil`
    /// (don't degrade the overall verdict) when the destination chain can't be
    /// screened or the scan provider is unavailable — the provider-side AML
    /// screening (SwapKit) and the on-device output-target verification remain
    /// the backstops in that case.
    private func scanRecipient(transaction: SwapTransaction) async -> SecurityScannerResult? {
        guard isScanningAvailable(for: transaction.toCoin.chain) else { return nil }
        do {
            let tx = try service.createRecipientSecurityScannerTransaction(transaction: transaction)
            return try await service.scanTransaction(tx)
        } catch {
            return nil
        }
    }

    /// The less-secure of two scan results: an insecure result always wins, and
    /// among insecure results the higher risk level wins.
    static func lessSecure(_ lhs: SecurityScannerResult, _ rhs: SecurityScannerResult) -> SecurityScannerResult {
        if lhs.isSecure != rhs.isSecure {
            return lhs.isSecure ? rhs : lhs
        }
        return lhs.riskLevel.severity >= rhs.riskLevel.severity ? lhs : rhs
    }

    func isScanningAvailable(for chain: Chain) -> Bool {
        guard service.isSecurityServiceEnabled() else { return false }
        // Check if any provider supports this chain for transaction scanning
        let supportedChains = service.getSupportedChainsByFeature()
        return supportedChains.contains { support in
            support.feature.contains { feature in
                feature.featureType == .scanTransaction && feature.chains.contains(chain)
            }
        }
    }

    private func update(state: SecurityScannerState) async {
        await MainActor.run { self.state = state }
    }

    private enum SecurityScannerTransactionType {
        case swap(SwapTransaction)
        case send(SendTransaction)
    }
}
