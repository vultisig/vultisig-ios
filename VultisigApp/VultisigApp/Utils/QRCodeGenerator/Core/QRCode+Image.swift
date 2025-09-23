import CoreGraphics
import Foundation

extension QRCode {
    func cgImage(
        _ size: CGSize,
        design: QRCodeDesign
    ) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
        else {
            return nil
        }

        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -size.height)

        self.draw(ctx: context, rect: CGRect(origin: .zero, size: size), design: design)

        let im = context.makeImage()
        return im
    }

    /// Draw the current qrcode into the context using the specified style
    func draw(ctx: CGContext, rect: CGRect, design: QRCodeDesign) {
        let style = design.style

        // Fill the background first
        ctx.usingGState { context in
            style.background.fill(ctx: context, rect: rect)
        }

        // Draw the outer eye
        let eyeOuterPath = self.path(rect.size, components: .eyeOuter, shape: design.shape)
        ctx.usingGState { context in
            let outerStyle = style.eye ?? style.onPixels
            outerStyle.fill(ctx: context, rect: rect, path: eyeOuterPath)
        }

        // Draw the eye 'pupil'
        let eyePupilPath = self.path(rect.size, components: .eyePupil, shape: design.shape)
        ctx.usingGState { context in
            let pupilStyle = style.pupil ?? style.eye ?? style.onPixels
            pupilStyle.fill(ctx: context, rect: rect, path: eyePupilPath)
        }

        // Now, the 'on' pixels
        let qrPath = self.path(rect.size, components: .onPixels, shape: design.shape)
        ctx.usingGState { context in
            style.onPixels.fill(ctx: context, rect: rect, path: qrPath)
        }
    }
}
