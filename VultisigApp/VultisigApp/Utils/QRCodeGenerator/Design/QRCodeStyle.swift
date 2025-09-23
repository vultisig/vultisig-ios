//
//  QRCodeStyle.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import CoreGraphics
import Foundation
import SwiftUI

struct QRCodeStyle {
    let onPixels = FillStyleSolid(Color.white.toCGColor)
    let eye: FillStyleSolid? = nil
    let pupil: FillStyleSolid? = nil
    let background = FillStyleSolid(Theme.colors.bgSecondary.toCGColor)
}
