//
//  QRCodeFillStyleSolid.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import Foundation
import CoreGraphics

struct FillStyleSolid {

    let color: CGColor

    init(_ color: CGColor) {
        self.color = color
    }

    func fill(ctx: CGContext, rect: CGRect) {
        ctx.setFillColor(color)
        ctx.fill(rect)
    }

    func fill(ctx: CGContext, path: CGPath) {
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }
}
