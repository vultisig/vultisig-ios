//
//  TonSignDisplayViewModel.swift
//  VultisigApp
//

import Foundation
import OSLog
import SwiftUI
import WalletCore

/// View model that decodes a TonConnect `[TonMessage]` payload, resolves
/// jetton metadata, and runs an emulation fallback for swaps the local decoder
/// doesn't recognise. Mirrors `useTonMessageDecode` + `useTonSimulation` from
/// the Vultisig Windows codebase.
///
/// Stays on the main actor — `@Published` state drives `SignTonDisplayView`,
/// and resolving metadata is best-effort (no errors propagate to the view).
@MainActor
final class TonSignDisplayViewModel: ObservableObject {

    /// One outgoing TON message, paired with the locally-decoded intent and
    /// any resolved jetton metadata. The view picks a layout based on
    /// `intent` / `swap`.
    struct Entry: Equatable, Identifiable {
        let id: Int
        let message: TonMessage
        let intent: TonMessageBodyIntent?
        var jettonCoin: TonJettonMetadataResolver.Resolved?
        var swapOutputCoin: TonJettonMetadataResolver.Resolved?

        var swap: TonMessageBodyIntent.Swap? {
            if case .swap(let swap) = intent { return swap }
            return nil
        }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var simulationSwap: TonSwapSimulator.SwapInfo?
    @Published private(set) var isSimulating: Bool = false

    private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-sign-display-view-model")

    private var lastDecodedKey: [String]?

    /// Refresh decoded state for the supplied payload + vault. No-op when the
    /// inputs match the previous run.
    func load(signTon: SignTon, keysignPayload: KeysignPayload?, vault: Vault, fromAddress: String) async {
        let key = cacheKey(signTon: signTon, vaultId: vault.pubKeyECDSA, fromAddress: fromAddress)
        if key == lastDecodedKey { return }
        lastDecodedKey = key

        let decoded = decodeLocally(signTon: signTon)
        entries = decoded
        simulationSwap = nil

        await resolveJettonMetadata(vault: vault)

        let hasLocalSwap = entries.contains { $0.swap != nil }
        if hasLocalSwap {
            return
        }

        guard let keysignPayload else { return }

        isSimulating = true
        let result = await TonSwapSimulator.simulate(keysignPayload: keysignPayload)
        isSimulating = false
        simulationSwap = result
    }

    /// Visible entries after applying the same filters Windows uses:
    ///
    /// - When a swap is the rendered hero (local intent OR simulation),
    ///   non-swap "sidecar" messages from-self with ≤ 0.01 TON are hidden.
    /// - When the simulation surfaces a swap, every per-message panel is
    ///   suppressed (the swap card is the entire summary).
    func visibleEntries(fromAddress: String) -> [Entry] {
        if simulationSwap != nil {
            return []
        }
        let hasSwap = entries.contains { $0.swap != nil }
        guard hasSwap else { return entries }

        return entries.filter { entry in
            if entry.swap != nil { return true }
            return !isSwapSidecar(entry: entry, fromAddress: fromAddress)
        }
    }

    // MARK: - Decoding

    private func decodeLocally(signTon: SignTon) -> [Entry] {
        signTon.tonMessages.enumerated().map { index, message in
            let intent = TonMessageBodyDecoder.decode(
                payload: message.payload,
                outerDestination: message.to
            )
            return Entry(
                id: index,
                message: message,
                intent: intent,
                jettonCoin: nil,
                swapOutputCoin: nil
            )
        }
    }

    private func resolveJettonMetadata(vault: Vault) async {
        for index in entries.indices {
            await resolveJettonForEntry(at: index, vault: vault)
        }
    }

    private func resolveJettonForEntry(at index: Int, vault: Vault) async {
        guard index < entries.count else { return }
        let entry = entries[index]

        let needsJetton: Bool
        switch entry.intent {
        case .jettonTransfer:
            needsJetton = true
        case .swap(let swap) where swap.offerAsset == .jetton:
            needsJetton = true
        default:
            needsJetton = false
        }

        if needsJetton {
            let jetton = await TonJettonMetadataResolver.resolve(
                jettonWalletAddress: entry.message.to,
                vault: vault
            )
            if index < entries.count {
                entries[index].jettonCoin = jetton
            }
        }

        if let swap = entry.swap, let target = swap.targetAddress, !target.isEmpty {
            let resolvedTarget = await TonJettonMetadataResolver.resolve(
                jettonWalletAddress: target,
                vault: vault
            )
            if index < entries.count {
                entries[index].swapOutputCoin = resolvedTarget
            }
        }
    }

    // MARK: - Helpers

    private func isSwapSidecar(entry: Entry, fromAddress: String) -> Bool {
        guard !fromAddress.isEmpty else { return false }
        let from = TONAddressConverter.toUserFriendly(
            address: fromAddress,
            bounceable: true,
            testnet: false
        ) ?? fromAddress
        let to = TONAddressConverter.toUserFriendly(
            address: entry.message.to,
            bounceable: true,
            testnet: false
        ) ?? entry.message.to
        guard from == to else { return false }
        // Any same-self message ≤ 0.01 TON is treated as the gas/sidecar
        // forward attached to a DEX swap, mirroring Windows' threshold of
        // 10_000_000 nanoton.
        guard let amount = UInt64(entry.message.amount) else { return false }
        return amount <= 10_000_000
    }

    private func cacheKey(signTon: SignTon, vaultId: String, fromAddress: String) -> [String] {
        var parts: [String] = [vaultId, fromAddress]
        for message in signTon.tonMessages {
            parts.append(message.to)
            parts.append(message.amount)
            parts.append(message.payload ?? "")
            parts.append(message.stateInit ?? "")
        }
        return parts
    }
}
