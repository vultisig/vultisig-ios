import CoreGraphics
import Foundation
import UIKit

struct QRCodePixelGenerator {

    let inset: CGFloat

    init(inset: CGFloat = 0) {
        self.inset = inset
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

                path.addPath(UIBezierPath(
                    roundedRect: ri,
                    byRoundingCorners: calculateRoundingCorners(row: row, col: col, data: data),
                    cornerRadii: CGSize(width: ri.width / 2, height: ri.height / 2)).cgPath)
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

    private func calculateRoundingCorners(row: Int, col: Int, data: QRCode) -> UIRectCorner {
        var corners: UIRectCorner = .allCorners

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
