//
//  CGMutablePath+LineHelpers.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import CoreGraphics

extension CGMutablePath {
    @inlinable @inline(__always) func curve(
        to endPoint: CGPoint,
        controlPoint1: CGPoint,
        controlPoint2: CGPoint
    ) {
        addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
    }

    @inlinable @inline(__always) func line(to point: CGPoint) { addLine(to: point) }
    @inlinable @inline(__always) func close() { closeSubpath() }
}
