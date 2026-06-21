//
//  LockedFeature.swift
//  VultisigApp
//

import Foundation

/// Descriptor for a tier-locked feature shown by `LockedFeatureSheet`.
///
/// Each case carries everything the generic sheet needs to render: the icon,
/// copy, and the minimum `VultDiscountTier` required to unlock it. The sheet
/// resolves the badge colour, threshold amount, and balance comparison from the
/// tier system (`VultDiscountTier` / `VultTierService`) — never from a design
/// mock. Add a case here to gate a new feature behind the same upsell sheet.
enum LockedFeature: Hashable {
    case customRPC
    case swapAdvancedSettings

    /// Asset-catalog icon rendered in the badge above the title.
    var icon: String {
        switch self {
        case .customRPC:
            return "signal-tower"
        case .swapAdvancedSettings:
            return "sliders"
        }
    }

    /// Localization key for the sheet title.
    var titleKey: String {
        switch self {
        case .customRPC:
            return "customRPCsLockedTitle"
        case .swapAdvancedSettings:
            return "swapAdvancedSettingsLockedTitle"
        }
    }

    /// Localization key for the supporting subtitle under the title.
    var subtitleKey: String {
        switch self {
        case .customRPC:
            return "customRPCsLockedSubtitle"
        case .swapAdvancedSettings:
            return "swapAdvancedSettingsLockedSubtitle"
        }
    }

    /// Minimum tier required to unlock the feature. Sourced from the gate, never
    /// from the design mock (which may show a different tier for layout).
    var requiredTier: VultDiscountTier {
        switch self {
        case .customRPC:
            return .silver
        case .swapAdvancedSettings:
            return .silver
        }
    }
}
