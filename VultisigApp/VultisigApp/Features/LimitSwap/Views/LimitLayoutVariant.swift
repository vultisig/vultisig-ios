//
//  LimitLayoutVariant.swift
//  VultisigApp
//

import Foundation

/// The four candidate layouts for the limit-swap form, carried side-by-side on
/// this **design-review branch** so they can be compared live in one build
/// instead of by rebuilding four branches.
///
/// Every case renders the SAME `LimitSwapFormViewModel`, memo math, validation,
/// routability gate and place-order flow — they differ in presentation only, so
/// a comparison between them is a comparison of layout and nothing else.
///
/// `String`-backed (not `Int`) so the dev's choice persists legibly through
/// `@AppStorage` and survives a relaunch; `@AppStorage`'s `RawRepresentable`
/// overload falls back to the declared default if the stored raw value no
/// longer maps to a case, so removing a variant can't wedge the screen.
enum LimitLayoutVariant: String, CaseIterable, Identifiable {

    /// Two-section accordion — Execute-when first, Asset second.
    case accordion

    /// Two-section accordion — Asset first, Execute-when second.
    case assetsFirst

    /// Flat: no accordion, every input visible at once.
    case uniswapFlat

    /// Three-section accordion — Asset → Execute when → Amount, the last
    /// carrying the reflected output.
    case threeSection

    var id: String { rawValue }

    /// Dev-facing label for the review picker. Deliberately NOT localized: this
    /// picker exists only on this never-merging review branch, behind the
    /// default-off `limitSwapEnabled` advanced setting, and is read by the devs
    /// and designers comparing the layouts — never by a shipping user. Adding
    /// four throwaway keys to eight locale files would be pure churn.
    var displayName: String {
        switch self {
        case .accordion:
            return "Accordion (current)"
        case .assetsFirst:
            return "Assets first"
        case .uniswapFlat:
            return "Uniswap flat"
        case .threeSection:
            return "Three sections"
        }
    }
}
