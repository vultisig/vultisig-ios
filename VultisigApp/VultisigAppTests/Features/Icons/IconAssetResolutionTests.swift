//
//  IconAssetResolutionTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Proves that every icon name an enum can produce resolves to a real asset.
///
/// Icons are looked up by string (`Icon(named: "bolt")`), so a typo or a missed
/// rename compiles cleanly and renders a blank rectangle at runtime. `make
/// lint-icons` catches most of that statically, but it is a heuristic and it is
/// explicitly NOT sound — the names below are the cases it is weakest on:
///
/// - `VultDiscountTier.icon` builds its name as `"vult-\(rawValue)"`, so no grep
///   or static scan can see it at all.
/// - The rest return names from a `switch`, reaching `Icon(named:)` through a
///   caller rather than at a literal call site.
///
/// A `CaseIterable` loop is the right tool here, and a strictly better one: it is
/// *sound* for these families (the compiler enumerates the cases, not a regex)
/// and it is self-maintaining — add an enum case with a bad icon name and this
/// fails, with no list to update.
///
/// Only enums whose string is an **asset** name belong here. Several types take
/// an `icon:` label but forward it to `Image(systemName:)`, where the string is
/// an SF Symbol; asserting those against the asset catalog would fail wrongly.
final class IconAssetResolutionTests: XCTestCase {

    private func assertResolves(_ name: String, _ source: String, line: UInt = #line) {
        #if canImport(UIKit)
        let exists = UIImage(named: name) != nil
        #else
        let exists = NSImage(named: name) != nil
        #endif
        XCTAssertTrue(
            exists,
            "\(source) yields icon \"\(name)\", which resolves to no asset — it renders as a blank rectangle.",
            line: line
        )
    }

    /// The interpolated one: `"vult-\(rawValue)"` is invisible to every static check.
    func testEveryVultDiscountTierIconResolves() {
        for tier in VultDiscountTier.allCases {
            assertResolves(tier.icon, "VultDiscountTier.\(tier.rawValue).icon")
        }
    }

    func testEveryCoinActionButtonIconResolves() {
        for action in CoinAction.allCases {
            assertResolves(action.buttonIcon, "CoinAction.\(action.rawValue).buttonIcon")
        }
    }

    func testEverySettingsOptionIconResolves() {
        for option in SettingsOption.allCases {
            guard let icon = option.icon else { continue }
            assertResolves(icon, "SettingsOption.\(option.rawValue).icon")
        }
    }

    func testEveryLockedFeatureIconResolves() {
        for feature in LockedFeature.allCases {
            assertResolves(feature.icon, "LockedFeature.\(feature).icon")
        }
    }

    func testEveryNotificationBannerStyleIconResolves() {
        for style in NotificationBannerStyle.allCases {
            assertResolves(style.iconName, "NotificationBannerStyle.\(style).iconName")
        }
    }

    func testEveryHomeTabIconResolves() {
        for tab in HomeTab.allCases {
            assertResolves(tab.icon, "HomeTab.\(tab).icon")
        }
    }

    func testEveryTronResourceTypeIconResolves() {
        for type in TronResourceType.allCases {
            guard let icon = type.icon else { continue }
            assertResolves(icon, "TronResourceType.\(type).icon")
        }
    }

    func testEveryVaultBannerTypeImageResolves() {
        for banner in VaultBannerType.allCases {
            assertResolves(banner.image, "VaultBannerType.\(banner).image")
        }
    }

    /// `DeviceInfo.iconName` is a static func over a signer string rather than an
    /// enum, so it is pinned by its known outcomes instead of by `allCases`.
    func testDeviceInfoSignerIconsResolve() {
        for signer in ["windows", "extension", "mac", "iPhone", "iPad"] {
            assertResolves(DeviceInfo.iconName(for: signer), "DeviceInfo.iconName(for: \"\(signer)\")")
        }
    }
}
