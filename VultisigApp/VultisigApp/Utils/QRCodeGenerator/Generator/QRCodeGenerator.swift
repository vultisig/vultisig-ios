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

        guard let logoImage = logoImage, logoImage.size.width != 0, logoImage.size.height != 0 else {
            return Image(uiImage: qrcodeImage)
        }
        
        let dataPixels = qrcode.pixelSize

        let pointsPerDataPixel: Int = Int(size.width) / dataPixels
        let totalLogoDimension = pointsPerDataPixel * (qrcode.paddedCutOutFrame.end - qrcode.paddedCutOutFrame.start)

        let logoAspectRatio: Double = logoImage.size.height / logoImage.size.width
        let width = logoAspectRatio > 1 ? CGFloat(Double(totalLogoDimension) / logoAspectRatio) : CGFloat(totalLogoDimension)
        let heigth = logoAspectRatio > 1 ? CGFloat(totalLogoDimension) : CGFloat(Double(totalLogoDimension) * logoAspectRatio)
        let x = (size.width - width) / 2.0
        let y = (size.height - heigth) / 2.0

        let logoSize = CGRect(
            x: x,
            y: y,
            width: width,
            height: heigth)

        return Image(uiImage: qrcodeImage.compose(with: logoImage, rect: logoSize))
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
