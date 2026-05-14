//
//  SwapDoneScreen.swift
//  VultisigApp
//

import SwiftUI
import OSLog
import Mediator

private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-done-screen")

struct SwapDoneScreen: View {
    let vault: Vault
    let hash: String
    let approveHash: String?
    let chain: Chain
    let transaction: SwapTransaction
    let progressLink: String?

    @State private var didPersistLimitOrder = false

    private let limitStorage = LimitOrderStorageService()

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                SendCryptoDoneView(
                    vault: vault,
                    hash: hash,
                    approveHash: approveHash,
                    chain: chain,
                    progressLink: progressLink,
                    sendTransaction: nil,
                    swapTransaction: transaction,
                    isSend: false
                )

                if transaction.isLimit {
                    limitOrdersInfoBanner
                        .padding(.horizontal, 16)
                }
            }
        }
        .screenTitle("done".localized)
        .screenBackButtonHidden()
        .onAppear {
            persistLimitOrderIfNeeded()
            Task {
                try? await Task.sleep(for: .seconds(5))
                Mediator.shared.stop()
            }
        }
    }

    /// Mirrors Figma 74765:106224 — info banner anchored above the bottom
    /// "Track / Done" actions on the limit-success state. Tells the user
    /// where to find their order in Transaction History.
    private var limitOrdersInfoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.colors.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("limitSwap.done.bannerTitle".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text("limitSwap.done.bannerDetail".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    @MainActor
    private func persistLimitOrderIfNeeded() {
        guard !didPersistLimitOrder,
              let context = transaction.limitContext,
              !hash.isEmpty else { return }
        didPersistLimitOrder = true
        let record = context.with(inboundTxHash: hash)
        do {
            _ = try limitStorage.persist(record, for: vault)
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
            status: status,
            memo: memo,
            expiryHours: expiryHours
        )
    }
}
