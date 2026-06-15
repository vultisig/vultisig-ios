//
//  SwapAdvancedSettings.swift
//  VultisigApp
//
//  Per-swap advanced settings: slippage tolerance, an optional EVM gas-limit
//  override, and an optional external recipient address. Owned by
//  `SwapDetailsViewModel` (form state) and copied into the immutable
//  `SwapTransaction` at hand-off. Reset to `.default` between swaps so a custom
//  slippage never sticks (Phase 5 reset semantics).
//

import BigInt
import Foundation

struct SwapAdvancedSettings: Equatable, Hashable {
    var slippage: SwapSlippage = .auto

    /// Custom EVM gas limit override. `nil` means Auto (use the estimated limit).
    /// EVM-only; ignored on non-EVM chains.
    var gasLimit: BigUInt?

    /// Final destination for the swapped funds. `nil` means "send to my own
    /// vault address" (today's behavior). When set, it MUST be surfaced on the
    /// verify screen before signing. Blank/whitespace-only input normalizes to
    /// `nil` so an empty recipient never marks the settings active or leaks
    /// downstream.
    var externalRecipient: String? {
        get { _externalRecipient }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            _externalRecipient = (trimmed?.isEmpty == false) ? trimmed : nil
        }
    }

    private var _externalRecipient: String?

    static let `default` = SwapAdvancedSettings()

    /// True when any setting deviates from its default — drives whether the
    /// "Advanced Settings" link shows an active indicator.
    var isActive: Bool {
        slippage != .auto || gasLimit != nil || externalRecipient != nil
    }
}
