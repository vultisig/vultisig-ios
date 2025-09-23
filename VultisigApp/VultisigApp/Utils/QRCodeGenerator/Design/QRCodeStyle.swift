import CoreGraphics
import Foundation
import SwiftUI

struct QRCodeStyle {
    let onPixels = FillStyleSolid(Color.white.toCGColor)
    let eye: FillStyleSolid? = nil
    let pupil: FillStyleSolid? = nil
    let background = FillStyleSolid(Theme.colors.bgSecondary.toCGColor)
}
