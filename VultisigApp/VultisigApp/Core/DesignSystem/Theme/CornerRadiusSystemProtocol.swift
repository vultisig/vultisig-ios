//
//  CornerRadiusSystemProtocol.swift
//  DesignSystem
//

import SwiftUI

/// The app's corner-radius scale.
///
/// The numeric steps are named by size, not by surface: `md` means "12 from the
/// scale", nothing more. Which surface class should use which step is
/// documentation (see the comments below), not a contract — that mapping is
/// still being reconciled against the design file, and encoding it in the token
/// names would freeze a half-verified answer.
///
/// `pill` is the one semantic token, because "fully rounded" is not a number.
/// The design file expresses it as 50, 77 or 99 depending on the component and
/// the app has 50, 60, 99 and 100 in use; all four mean the same thing, and the
/// token collapses them so no call site imports another magic number.
public protocol CornerRadiusSystemProtocol {
    /// 4 — progress tracks, skeleton bars, hairline chips.
    var xs: CornerRadius { get }
    /// 8 — small inline tags.
    var sm: CornerRadius { get }
    /// 12 — list rows, compact containers.
    var md: CornerRadius { get }
    /// 16 — input fields, inner icon tiles.
    var lg: CornerRadius { get }
    /// 24 — cards, banners, list containers.
    var xl: CornerRadius { get }
    /// 38 — sheets and modals.
    var xxl: CornerRadius { get }
    /// Fully rounded, at every surface size the app can render.
    var pill: CornerRadius { get }
}
