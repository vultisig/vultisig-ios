import CoreGraphics
import CoreImage
import Foundation
import SwiftUI

struct QRCodeGenerator {
    private let context = CIContext()
    
    func generateImage(
        utf8String: String,
        size: CGSize,
        logoImage: UIImage?,
        scale: CGFloat
    ) -> Image? {
        let design = QRCodeDesign()
        let data = utf8String.data(using: .utf8) ?? Data()
        let qrcode = QRCode(data)
        let coreSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard let qrImage = qrcode.cgImage(coreSize, design: design) else { return nil }
        let qrcodeImage = UIImage(cgImage: qrImage, scale: scale, orientation: .up)

        guard let logoImage = logoImage else {
            return Image(uiImage: qrcodeImage)
        }
        
        let logoTargetSize = CGSize(width: size.width / 4, height: size.height / 4)
        
        // Create a resized logo using UIGraphicsImageRenderer for guaranteed scaling
        let resizedLogo: UIImage
        let renderer = UIGraphicsImageRenderer(size: logoTargetSize)
        resizedLogo = renderer.image { context in
            logoImage.draw(in: CGRect(origin: .zero, size: logoTargetSize))
        }
        
        // Position the resized logo in the center of the QR code
        let logoRect = CGRect(
            x: (size.width - logoTargetSize.width) / 2.0,
            y: (size.height - logoTargetSize.height) / 2.0,
            width: logoTargetSize.width,
            height: logoTargetSize.height
        )

        return Image(uiImage: qrcodeImage.compose(with: resizedLogo, rect: logoRect))
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
