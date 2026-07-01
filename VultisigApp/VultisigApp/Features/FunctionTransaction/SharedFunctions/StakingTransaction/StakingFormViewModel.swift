//
//  StakingFormViewModel.swift
//  VultisigApp
//
//  Descriptor protocol the generic `StakingTransactionScreen` renders. A
//  conforming form view-model exposes value-typed specs — an optional amount
//  section, an optional validator picker, read-only display rows, and a notices
//  list — plus the `transactionBuilder` to hand to Verify. No SwiftUI lives in
//  the view-model: the screen turns these specs into views, so the same screen
//  drives the Cosmos delegate/undelegate and Solana delegate/unstake/withdraw
//  forms.
//

import Foundation

@MainActor
protocol StakingFormViewModel: ObservableObject, Form {
    /// The coin being staked — drives the title's ticker + the notices.
    var coin: Coin { get }
    /// Localized title key, formatted with `coin.ticker` by the screen.
    var titleKey: String { get }
    /// Hard-disables Continue regardless of `validForm` (e.g. insufficient fee,
    /// or a not-yet-withdrawable account).
    var isContinueDisabled: Bool { get }
    /// Amount input section, or `nil` for confirm-only screens.
    var amountSpec: StakingAmountSpec? { get }
    /// Editable validator picker section, or `nil` when there is none.
    var pickerSpec: StakingPickerSpec? { get }
    /// Read-only display rows (e.g. the pre-selected stake account / amount).
    var readOnlyRows: [StakingReadOnlyRow] { get }
    /// Notices to render below the form, already resolved for the current state.
    var notices: [StakingNotice] { get }
    /// The builder handed to Verify, or `nil` while the form is incomplete.
    var transactionBuilder: TransactionBuilder? { get }

    func onLoad()
    /// Called when the amount-field percentage changes. No-op by default for
    /// confirm-only screens.
    func onPercentage(_ percentage: Double)
}

extension StakingFormViewModel {
    var amountSpec: StakingAmountSpec? { nil }
    var pickerSpec: StakingPickerSpec? { nil }
    var readOnlyRows: [StakingReadOnlyRow] { [] }
    func onPercentage(_: Double) {}
}

/// Amount-input section spec. `field` is the form's `FormField` (a reference, so
/// its `$value`/`$error` drive the text field); the rest configure the
/// `AmountTextField`.
struct StakingAmountSpec {
    let field: FormField
    /// `.button` (delegate) or `.slider` (undelegate) percentage selector.
    let type: PercentageFieldType
    /// Headroom-aware available balance the "Max"/percentage path bounds to.
    let availableAmount: Decimal
    let decimals: Int
    let ticker: String
    /// Seed the field to the full available amount (100%) on load — undelegate
    /// pre-fills the whole staked balance.
    let seedMaxOnLoad: Bool
}

/// Editable validator-picker section spec. The sheet itself is supplied to the
/// screen separately (it binds the chain-specific selection), so this only
/// carries the row's display state.
struct StakingPickerSpec {
    let title: String
    let isSelected: Bool
    /// Identity of the current selection — drives the amount-refocus on change.
    let selectionToken: String?
    /// Inline preview of the current selection, or `nil` when nothing's picked.
    let preview: StakingValidatorPreview?
}

/// Inline preview of a selected validator. `avatar` is `nil` for chains whose
/// selection preview shows the name only (Solana).
struct StakingValidatorPreview {
    let name: String
    let avatar: StakingValidator.Avatar?
}

/// A non-interactive display row (disabled picker row) — a pre-selected stake
/// account or a computed withdrawable amount.
struct StakingReadOnlyRow: Identifiable {
    var id: String { title }
    let title: String
    let value: String
}

/// A notice rendered below the form.
enum StakingNotice: Identifiable, Equatable {
    /// Informational cooldown / unbonding copy (`InfoBannerView`).
    case info(String)
    /// Liquid-balance-below-fee warning (`InsufficientFeeNotice`).
    case insufficientFee(ticker: String)

    var id: String {
        switch self {
        case .info(let message):
            return "info-\(message)"
        case .insufficientFee:
            return "insufficient-fee"
        }
    }
}
