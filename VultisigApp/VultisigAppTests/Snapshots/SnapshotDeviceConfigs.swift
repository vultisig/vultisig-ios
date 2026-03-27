//
//  SnapshotDeviceConfigs.swift
//  VultisigAppTests
//

import SnapshotTesting
import UIKit

extension ViewImageConfig {

    /// iPhone 16 Pro — 393×852pt @3x, 59pt top safe area, 34pt bottom
    static let iPhone16Pro = ViewImageConfig.iPhone16Pro(.portrait)

    static func iPhone16Pro(_ orientation: Orientation) -> ViewImageConfig {
        let safeArea: UIEdgeInsets
        let size: CGSize
        switch orientation {
        case .landscape:
            safeArea = .init(top: 0, left: 59, bottom: 21, right: 59)
            size = .init(width: 852, height: 393)
        case .portrait:
            safeArea = .init(top: 59, left: 0, bottom: 34, right: 0)
            size = .init(width: 393, height: 852)
        }
        return .init(safeArea: safeArea, size: size, traits: .iPhone16Pro(orientation))
    }

    /// iPhone 16 — 393×852pt @3x, 59pt top safe area, 34pt bottom (same as 16 Pro)
    static let iPhone16 = iPhone16Pro
}

extension UITraitCollection {

    static func iPhone16Pro(_ orientation: ViewImageConfig.Orientation) -> UITraitCollection {
        let base: [UITraitCollection] = [
            .init(forceTouchCapability: .unavailable),
            .init(layoutDirection: .leftToRight),
            .init(preferredContentSizeCategory: .medium),
            .init(userInterfaceIdiom: .phone),
            .init(displayScale: 3)
        ]
        switch orientation {
        case .landscape:
            return .init(traitsFrom: base + [
                .init(horizontalSizeClass: .regular),
                .init(verticalSizeClass: .compact)
            ])
        case .portrait:
            return .init(traitsFrom: base + [
                .init(horizontalSizeClass: .compact),
                .init(verticalSizeClass: .regular)
            ])
        }
    }
}
