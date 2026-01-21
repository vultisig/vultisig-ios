//
//  ScreenEdgeInsets.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/08/2025.
//

import SwiftUI

struct ScreenEdgeInsets {
    let top: CGFloat?
    let leading: CGFloat?
    let bottom: CGFloat?
    let trailing: CGFloat?

    init(
        top: CGFloat? = nil,
        leading: CGFloat? = nil,
        bottom: CGFloat? = nil,
        trailing: CGFloat? = nil
    ) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    static let noInsets = ScreenEdgeInsets()
}
