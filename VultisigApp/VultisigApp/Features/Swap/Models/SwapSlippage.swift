//
//  SwapSlippage.swift
//  VultisigApp
//
//  User-selectable slippage tolerance for a swap. `Auto` preserves each
//  provider's existing default (no caller override); the explicit cases carry a
//  basis-points value threaded into every provider's quote/tx request.
//

import Foundation

enum SwapSlippage: Equatable, Hashable {
    /// Keep today's per-provider default — no caller-supplied slippage.
    case auto
    /// A preset slippage in basis points (e.g. 50 = 0.5%, 100 = 1%, 300 = 3%).
    case preset(bps: Int)
    /// A user-entered custom slippage in basis points.
    case custom(bps: Int)

    /// Preset options shown as radio rows (Auto and Custom are rendered separately).
    static let presets: [Int] = [50, 100, 300]

    /// Upper bound on a custom slippage (basis points). Matches the downstream
    /// aggregator clamp (1inch/LI.FI cap at 5000 bps = 50%); THORChain/Maya pass
    /// `liquidity_tolerance_bps` raw and KyberSwap/SwapKit forward without an upper
    /// clamp, so the cap is enforced here at the input layer to keep an absurd
    /// `liquidity_tolerance_bps` off the wire entirely.
    static let maxCustomBps = 5000

    /// Clamp a custom slippage to `0...maxCustomBps`.
    static func clampCustomBps(_ bps: Int) -> Int {
        min(max(bps, 0), maxCustomBps)
    }

    /// Basis points to send to providers, or `nil` for `Auto` (keep the default).
    var bps: Int? {
        switch self {
        case .auto:
            return nil
        case let .preset(bps), let .custom(bps):
            return bps
        }
    }

    /// Display value for the Advanced Settings "Slippage Tolerance" row.
    var displayValue: String {
        switch self {
        case .auto:
            return "auto".localized
        case let .preset(bps), let .custom(bps):
            return Self.format(bps: bps)
        }
    }

    /// Format a basis-points value as a trimmed percentage string (e.g. `0.5%`).
    static func format(bps: Int) -> String {
        let percent = Decimal(bps) / 100
        let number = NSDecimalNumber(decimal: percent)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        // Force a dot separator so the displayed percentage is stable across locales.
        formatter.decimalSeparator = "."
        let formatted = formatter.string(from: number) ?? "\(percent)"
        return "\(formatted)%"
    }
}
