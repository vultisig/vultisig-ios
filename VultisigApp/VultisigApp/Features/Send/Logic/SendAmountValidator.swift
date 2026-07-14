//
//  SendAmountValidator.swift
//  VultisigApp
//
//  Chain-agnostic async pre-flight checks on the Send form's amount. A
//  validator inspects a value-type snapshot of the current form input and
//  returns either "no objection" or an inline message that can also veto the
//  Continue button. Keeping the per-chain policy behind this protocol lets
//  `SendDetailsViewModel` stay chain-agnostic — a new chain adds a validator
//  rather than another branch in the VM.
//

import BigInt
import Foundation

/// An async check run against the Send form's amount while the user fills the
/// form in. The XRP base-reserve check (`RippleDestinationReserveValidator`) is
/// the first implementation.
protocol SendAmountValidator {
    /// Whether this validator applies to `input`. Cheap, pure and
    /// side-effect-free — the VM uses it to skip async work (and to clear any
    /// stale message synchronously) before scheduling a check.
    func isApplicable(to input: SendAmountValidationInput) -> Bool

    /// Runs the check for `input`.
    /// - Parameter forceRefresh: bypass any per-validator cache. The
    ///   while-typing path leaves this `false`; the Continue-time gate passes
    ///   `true` so its decision is always live.
    func validate(_ input: SendAmountValidationInput, forceRefresh: Bool) async -> SendAmountValidatorResult
}

/// Immutable snapshot of the form inputs a validator reads. Carries value types
/// only (never the `@Model` `Coin`) so it's safe to hand to an async validator
/// off the main actor.
struct SendAmountValidationInput: Equatable {
    let chain: Chain
    let isNativeToken: Bool
    let toAddress: String
    let amount: String
    let amountDecimal: Decimal
    let amountRaw: BigInt
}

/// The outcome of a single validator run.
enum SendAmountValidatorResult: Equatable {
    /// No objection: nothing to show, Continue is not blocked by this validator.
    case ok
    /// Present `message` inline under the amount field. When `blocksContinue`
    /// is `true`, Continue is disabled while the message is shown.
    case invalid(message: String, blocksContinue: Bool)
}

/// The published result of the VM's amount validation: the inline message to
/// render (if any) and whether it blocks Continue. `Equatable` so SwiftUI can
/// drive the `verticalGrowAndFade` transition off value changes.
struct SendAmountValidationState: Equatable {
    var message: String?
    var blocksContinue: Bool

    /// No inline message; Continue not blocked.
    static let valid = SendAmountValidationState(message: nil, blocksContinue: false)
}
