//
//  LogFeature.swift
//  VultisigApp
//
//  Feature axis of the logging taxonomy. Combined with `LogLayer` it forms the
//  OSLog category `"<feature>.<layer>"` (e.g. `swap.service`), so Console and
//  `log stream` can filter one feature (`category BEGINSWITH "swap"`) or one
//  layer across features (`category ENDSWITH ".network"`).
//
//  Cases are derived from the survey of existing `Logger(category:)` declarations
//  (see wiki `logging-wrapper/analysis.md`). The rawValue is the category prefix.
//

import Foundation

/// A coarse product area used as the first segment of an OSLog category.
enum LogFeature: String, CaseIterable, Sendable {
    /// Vault creation / keygen ceremony (`Features/Keygen`, `Blockchain/States/Keygen`).
    case keygen
    /// Transaction signing ceremony (`Features/Keysign`, `Blockchain/States/Keysign`).
    case keysign
    /// Low-level MPC transport & messengers (`Blockchain/Tss`, `Blockchain/Common`, `Mediator`).
    case tss
    /// Swaps, limit swaps and swap providers (`Features/Swap`, `Features/LimitSwap`, `Blockchain/Swaps`).
    case swap
    /// Send / deposit / function-call transaction composition (`Features/Send`, `Features/FunctionCall`, `Features/FunctionTransaction`).
    case send
    /// Staking, bonding, LPs and yield (`Features/Defi`).
    case defi
    /// QBTC claim, governance and proof (`Features/QBTCClaim`, `Blockchain/Cosmos/**/QBTC`).
    case qbtc
    /// Per-chain blockchain services & signers plus cross-chain data services (`Blockchain/<Chain>`, `Core/Services`).
    case chain
    /// Wallet home, transaction history, referral, backup and shared stores/view-models.
    case wallet
    /// Cross-cutting app infrastructure (networking, security, platform, utils, notifications, onboarding, misc).
    case app
}
