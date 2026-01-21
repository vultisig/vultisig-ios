//
//  QRCode.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import CoreGraphics
import Foundation

struct QRCode {

    private var generator = QRCodeGenerator()
    private let errorCorrection: QRCodeErrorCorrection = .high
    private let logoContentAreaPercentage = 0.75
    private let paddingPercentage = 0.4
    private let maximumAllowedLogoPercentage = 0.4
    private let enableLogoCutout: Bool

    init(_ data: Data, enableLogoCutout: Bool = true) {
        self.enableLogoCutout = enableLogoCutout

        guard let result = self.generator.generate(data, errorCorrection: errorCorrection.rawValue) else {
            self.current = BoolMatrix()
            return
        }

        self.current = result
    }

    /// The QR code content as a 2D array of bool values
    private(set) var current = BoolMatrix()

    /// This is the pixel dimension for the QR Code.
    var pixelSize: Int {
        return self.current.dimension
    }

    var boolMatrix: BoolMatrix {
        self.current
    }

    var cutOutFrameRange: (start: Int, end: Int) {
        // If cutout is disabled, return a range that includes no pixels
        guard enableLogoCutout else {
            return (0, 0)
        }

        let pointSize = pixelSize.isOdd ? pixelSize - 1 : pixelSize
        let center = pixelSize / 2

        let reservedPointsForEye: Int = 9
        let cutOutFrame = Int(Double(pointSize - 2 * reservedPointsForEye) * logoContentAreaPercentage / 2)
        let finalSize = min(cutOutFrame, Int(Double(pointSize) * maximumAllowedLogoPercentage / 2.0))
        return (center - finalSize, center + finalSize)
    }

    var paddedCutOutFrame: (start: Int, end: Int) {
        // If cutout is disabled, return a range that includes no pixels
        guard enableLogoCutout else {
            return (0, 0)
        }

        let logoCutOutPercenatge = 1 - paddingPercentage
        let cutOutFrame = cutOutFrameRange
        return (Int(Double(cutOutFrame.start) * logoCutOutPercenatge), Int(Double(cutOutFrame.end) * logoCutOutPercenatge))
    }
}

// MARK: - Eye positioning/paths

extension QRCode {
    func isEyePixel(_ row: Int, _ col: Int) -> Bool {
        if row < 9 {
            if col < 9 {
                return true
            }
            if col >= (self.pixelSize - 9) {
                return true
            }
        } else if row >= (self.pixelSize - 9), col < 9 {
            return true
        }
        return false
    }
}
