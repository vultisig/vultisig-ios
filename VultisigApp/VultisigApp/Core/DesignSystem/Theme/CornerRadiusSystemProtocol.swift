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
///
/// **There is deliberately no sheet token, and the scale stops at 24.** The two
/// sheet frames in the design file measure 38 and 28, but both are stock
/// design-kit components dropped into the file rather than authored Vultisig
/// surfaces — the 38 one is Apple's iOS 26 sheet, the 28 one is Material 3.
/// Neither number is ours to own, and sheets already get the right radius from
/// native presentation. Adding a step for them would encode a platform default
/// as a design decision and invite a real sheet to diverge from the platform.
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
    /// Fully rounded, at every surface size the app can render.
    var pill: CornerRadius { get }
}
