//
//  LimitSwapDoneScreen.swift
//  VultisigApp
//
//  Terminal screen for the limit-swap pipeline. On appear, splices the
//  inbound TX hash into the pending `LimitOrderRecord` and persists it
//  via `LimitOrderStorageService` so the order shows up in the user's
//  limit-orders list.
//
//  Visual treatment piggybacks on `SendCryptoDoneContentView` rather
//  than the market `SwapDoneScreen` because limit orders don't have a
//  quote / to-amount to render. Same "transaction broadcast" shape as
//  a plain send with a memo.
//

import Mediator
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "limit-swap-done")

struct LimitSwapDoneScreen: View {
    let vault: Vault
    let hash: String
    let chain: Chain
    let pendingRecord: LimitOrderRecord

    @State private var didPersist = false

    private let storage = LimitOrderStorageService()

    var body: some View {
        Screen {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.colors.alertSuccess)

                VStack(spacing: 8) {
                    Text("limitSwap.done.title".localized)
                        .font(Theme.fonts.bodyLMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    Text("limitSwap.done.detail".localized)
                        .font(Theme.fonts.bodySRegular)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Text(hash)
                    .font(Theme.fonts.priceBodyS)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .screenTitle("done".localized)
        .screenBackButtonHidden()
        .onAppear {
            persistIfNeeded()
            Task {
                try? await Task.sleep(for: .seconds(5))
                Mediator.shared.stop()
            }
        }
    }

    @MainActor
    private func persistIfNeeded() {
        guard !didPersist, !hash.isEmpty else { return }
        didPersist = true
        let record = pendingRecord.with(inboundTxHash: hash)
        do {
            _ = try storage.persist(record, for: vault)
        } catch {
            // Duplicate on retry is benign; everything else is logged but
            // doesn't surface — broadcast already succeeded.
            logger.warning("Failed to persist limit order: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension LimitOrderRecord {
    /// Returns a copy with the inbound tx hash filled in. Used by the
    /// done screen to splice the broadcast result into the record before
    /// handing it to `LimitOrderStorageService.persist`.
    func with(inboundTxHash: String) -> LimitOrderRecord {
        LimitOrderRecord(
            inboundTxHash: inboundTxHash,
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            sourceDecimals: sourceDecimals,
            targetAsset: targetAsset,
            destAddress: destAddress,
            targetPrice: targetPrice,
            expiryBlocks: expiryBlocks,
            createdAt: createdAt,
            status: status
        )
    }
}
