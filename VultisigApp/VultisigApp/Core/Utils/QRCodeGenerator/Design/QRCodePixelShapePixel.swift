//
//  QRCodePixelGenerator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct QRCodePixelGenerator {

    let inset: CGFloat

    init(inset: CGFloat = 0) {
        self.inset = inset
    }

    // Cross-platform corner representation
    struct RoundingCorners: OptionSet {
        let rawValue: Int

        static let topLeft = RoundingCorners(rawValue: 1 << 0)
        static let topRight = RoundingCorners(rawValue: 1 << 1)
        static let bottomLeft = RoundingCorners(rawValue: 1 << 2)
        static let bottomRight = RoundingCorners(rawValue: 1 << 3)
        static let allCorners: RoundingCorners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    private func path(size: CGSize, data: QRCode, isOn: Bool) -> CGPath {
        guard data.pixelSize != 0 else { return CGMutablePath() }

        let dx = size.width / CGFloat(data.pixelSize)
        let dy = size.height / CGFloat(data.pixelSize)
        let dm = min(dx, dy)

        let xoff = (size.width - (CGFloat(data.pixelSize) * dm)) / 2.0
        let yoff = (size.height - (CGFloat(data.pixelSize) * dm)) / 2.0

        let path = CGMutablePath()

        for row in 0 ..< data.pixelSize {
            for col in 0 ..< data.pixelSize {
                if data.current[row, col] != isOn {
                    continue
                }

                if !isOn {
                    if row == 0 || col == 0 || row == data.pixelSize - 1 || col == data.pixelSize - 1 {
                        continue
                    }
                }

                if data.isEyePixel(row, col) {
                    // skip it
                    continue
                }

                if isInsideCutOutFrame(row: row, col: col, data: data) {
                    continue
                }

                let r = CGRect(x: xoff + (CGFloat(col) * dm), y: yoff + (CGFloat(row) * dm), width: dm, height: dm)
                let ri = r.insetBy(dx: self.inset, dy: self.inset)

#if canImport(UIKit)
                let uiCorners = convertToUIRectCorner(calculateRoundingCorners(row: row, col: col, data: data))
                path.addPath(UIBezierPath(
                    roundedRect: ri,
                    byRoundingCorners: uiCorners,
                    cornerRadii: CGSize(width: ri.width / 2, height: ri.height / 2)).cgPath)
#elseif canImport(AppKit)
                let bezierPath = createRoundedRectPath(rect: ri, corners: calculateRoundingCorners(row: row, col: col, data: data))
                path.addPath(bezierPath)
#endif
            }
        }
        return path
    }

    func onPath(size: CGSize, data: QRCode) -> CGPath {
        return self.path(size: size, data: data, isOn: true)
    }

    func offPath(size: CGSize, data: QRCode) -> CGPath {
        return self.path(size: size, data: data, isOn: false)
    }

#if canImport(UIKit)
    private func convertToUIRectCorner(_ corners: RoundingCorners) -> UIRectCorner {
        var uiCorners: UIRectCorner = []

        if corners.contains(.topLeft) {
            uiCorners.insert(.topLeft)
        }
        if corners.contains(.topRight) {
            uiCorners.insert(.topRight)
        }
        if corners.contains(.bottomLeft) {
            uiCorners.insert(.bottomLeft)
        }
        if corners.contains(.bottomRight) {
            uiCorners.insert(.bottomRight)
        }

        return uiCorners
    }
#endif

#if canImport(AppKit)
    private func createRoundedRectPath(rect: CGRect, corners: RoundingCorners) -> CGPath {
        let path = CGMutablePath()
        let radius = min(rect.width, rect.height) / 2

        if corners == .allCorners && radius > 0 {
            // Simple case - all corners rounded
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        } else {
            // Custom corner rounding
            let minX = rect.minX
            let minY = rect.minY
            let maxX = rect.maxX
            let maxY = rect.maxY

            path.move(to: CGPoint(x: minX + (corners.contains(.topLeft) ? radius : 0), y: minY))

            // Top edge
            path.addLine(to: CGPoint(x: maxX - (corners.contains(.topRight) ? radius : 0), y: minY))

            // Top right corner
            if corners.contains(.topRight) && radius > 0 {
                path.addArc(center: CGPoint(x: maxX - radius, y: minY + radius),
                           radius: radius, startAngle: -CGFloat.pi/2, endAngle: 0, clockwise: false)
            }

            // Right edge
            path.addLine(to: CGPoint(x: maxX, y: maxY - (corners.contains(.bottomRight) ? radius : 0)))

            // Bottom right corner
            if corners.contains(.bottomRight) && radius > 0 {
                path.addArc(center: CGPoint(x: maxX - radius, y: maxY - radius),
                           radius: radius, startAngle: 0, endAngle: CGFloat.pi/2, clockwise: false)
            }

            // Bottom edge
            path.addLine(to: CGPoint(x: minX + (corners.contains(.bottomLeft) ? radius : 0), y: maxY))

            // Bottom left corner
            if corners.contains(.bottomLeft) && radius > 0 {
                path.addArc(center: CGPoint(x: minX + radius, y: maxY - radius),
                           radius: radius, startAngle: CGFloat.pi/2, endAngle: CGFloat.pi, clockwise: false)
            }

            // Left edge
            path.addLine(to: CGPoint(x: minX, y: minY + (corners.contains(.topLeft) ? radius : 0)))

            // Top left corner
            if corners.contains(.topLeft) && radius > 0 {
                path.addArc(center: CGPoint(x: minX + radius, y: minY + radius),
                           radius: radius, startAngle: CGFloat.pi, endAngle: -CGFloat.pi/2, clockwise: false)
            }

            path.closeSubpath()
        }

        return path
    }
#endif

    private func calculateRoundingCorners(row: Int, col: Int, data: QRCode) -> RoundingCorners {
        var corners: RoundingCorners = .allCorners

        if isNeighbourValueOn(row: row, col: col - 1, data: data) {
            corners.remove(.bottomLeft)
            corners.remove(.topLeft)
        }

        if isNeighbourValueOn(row: row, col: col + 1, data: data) {
            corners.remove(.bottomRight)
            corners.remove(.topRight)
        }

        if isNeighbourValueOn(row: row - 1, col: col, data: data) {
            corners.remove(.topLeft)
            corners.remove(.topRight)
        }

        if isNeighbourValueOn(row: row + 1, col: col, data: data) {
            corners.remove(.bottomLeft)
            corners.remove(.bottomRight)
        }

        return corners
    }

    private func isNeighbourValueOn(row: Int, col: Int, data: QRCode) -> Bool {
        if row < 0 || col < 0 || row > data.pixelSize - 1 || col > data.pixelSize - 1 {
            return false
        }

        if data.current[row, col] != true {
            return false
        }

        if data.isEyePixel(row, col) {
            return false
        }

        if isInsideCutOutFrame(row: row, col: col, data: data) {
            return false
        }

        return true
    }

    private func isInsideCutOutFrame(row: Int, col: Int, data: QRCode) -> Bool {
        let cutOutFrameRange = data.cutOutFrameRange
        let center = Double(data.pixelSize) / 2.0
        let radius = Double(cutOutFrameRange.end - cutOutFrameRange.start) / 2.0

        // Calculate distance from center
        let deltaX = Double(col) - center + 0.5 // +0.5 to center the pixel
        let deltaY = Double(row) - center + 0.5
        let distanceFromCenter = sqrt(deltaX * deltaX + deltaY * deltaY)

        return distanceFromCenter <= radius
    }
}
