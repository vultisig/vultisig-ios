//
//  QRCodeGenerator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import CoreGraphics
import CoreImage
import Foundation
import SwiftUI

struct QRCodeGenerator {
    private let context = CIContext()

    func generateImage(
        qrStringData: String,
        size: CGSize,
        logoImage: PlatformImage? = nil,
        scale: CGFloat,
        bgColor: Color? = nil
    ) -> Image? {
        let data = qrStringData.data(using: .utf8) ?? Data()
        let qrcode = QRCode(data, enableLogoCutout: logoImage != nil)
        let coreSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard let qrImage = qrcode.cgImage(coreSize, shape: QRCodeShape(), style: QRCodeStyle(background: bgColor)) else { return nil }

        #if os(iOS)
        let qrcodeImage = UIImage(cgImage: qrImage, scale: scale, orientation: .up)
        #elseif os(macOS)
        let qrcodeImage = NSImage(cgImage: qrImage, size: size)
        #endif

        guard let logoImage = logoImage else {
            #if os(iOS)
            return Image(uiImage: qrcodeImage)
            #elseif os(macOS)
            return Image(nsImage: qrcodeImage)
            #endif
        }

        // Use the actual QR code image size for proper positioning and scaling
        #if os(iOS)
        let qrActualSize = qrcodeImage.size
        #elseif os(macOS)
        let qrActualSize = qrcodeImage.size
        #endif

        // Calculate target logo size - use 1/4 for good visibility
        let targetLogoSize = min(qrActualSize.width, qrActualSize.height) / 4.0

        // Create a resized logo using platform-specific graphics context
        let resizedLogo: PlatformImage

        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetLogoSize, height: targetLogoSize))
        resizedLogo = renderer.image { _ in
            logoImage.draw(in: CGRect(origin: .zero, size: CGSize(width: targetLogoSize, height: targetLogoSize)))
        }
        #elseif os(macOS)
        let macOSLogoSize = CGSize(width: targetLogoSize / 2, height: targetLogoSize / 2)
        resizedLogo = logoImage.resized(to: macOSLogoSize)
        #endif

        // Position the resized logo in the center of the QR code
        let logoRect = CGRect(
            x: (qrActualSize.width - targetLogoSize) / 2.0,
            y: (qrActualSize.height - targetLogoSize) / 2.0,
            width: targetLogoSize,
            height: targetLogoSize
        )

        let finalImage = qrcodeImage.compose(with: resizedLogo, rect: logoRect)
        #if os(iOS)
        return Image(uiImage: finalImage)
        #elseif os(macOS)
        return Image(nsImage: finalImage)
        #endif
    }

    func generate(_ data: Data, errorCorrection: String) -> BoolMatrix? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(errorCorrection, forKey: "inputCorrectionLevel")

        guard
            let outputImage = filter.outputImage,
            let qrImage = context.createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        let w = qrImage.width
        let h = qrImage.height
        let colorspace = CGColorSpaceCreateDeviceGray()

        var rawData = [UInt8](repeating: 0, count: w * h)
        rawData.withUnsafeMutableBytes { rawBufferPointer in
            if let rawPtr = rawBufferPointer.baseAddress {
                let context = CGContext(
                    data: rawPtr,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w,
                    space: colorspace,
                    bitmapInfo: 0
                )
                context?.draw(qrImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }

        return BoolMatrix(dimension: w, flattened: rawData.map { $0 == 0 ? true : false })
    }
}
