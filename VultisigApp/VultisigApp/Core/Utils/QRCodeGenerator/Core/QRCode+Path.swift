//
//  QRCode+Path.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/09/2025.
//

import CoreGraphics
import Foundation

extension QRCode {
    struct Components: OptionSet {
        let rawValue: Int

        static let eyeOuter = Components(rawValue: 1 << 0)
        static let eyePupil = Components(rawValue: 1 << 1)
        static let onPixels = Components(rawValue: 1 << 2)

        static let all: Components = [Components.eyeOuter, Components.eyePupil, Components.onPixels]

        public func contains(_ member: QRCode.Components) -> Bool {
            return (self.rawValue & member.rawValue) != 0
        }
    }

    func path(
        _ size: CGSize,
        components: Components = .all,
        shape: QRCodeShape = QRCodeShape()
    ) -> CGPath {
        if self.pixelSize == 0 {
            return CGPath(rect: .zero, transform: nil)
        }

        let dx = size.width / CGFloat(self.pixelSize)
        let dy = size.height / CGFloat(self.pixelSize)

        let dm = min(dx, dy)

        let xoff = (size.width - (CGFloat(self.pixelSize) * dm)) / 2.0
        let yoff = (size.height - (CGFloat(self.pixelSize) * dm)) / 2.0
        let posTransform = CGAffineTransform(translationX: xoff, y: yoff)

        let fitScale = (dm * 9) / 90
        var scaleTransform = CGAffineTransform.identity
        scaleTransform = scaleTransform.scaledBy(x: fitScale, y: fitScale)

        let path = CGMutablePath()

        // The outer part of the eye
        let eyeShape = shape.eye
        if components.contains(.eyeOuter) {
            let p = eyeShape.eyePath()
            var scaledTopLeft = scaleTransform.concatenating(posTransform)

            // top left
            if let tl = p.copy(using: &scaledTopLeft) {
                path.addPath(tl)
            }

            // bottom left
            var blt = CGAffineTransform(scaleX: 1, y: -1)
                .concatenating(CGAffineTransform(translationX: 0, y: 90))
                .concatenating(scaledTopLeft)

            var bltrans = CGAffineTransform(translationX: 0, y: (dm * CGFloat(self.pixelSize)) - (9 * dm))
            if let bl = p.copy(using: &blt), let blFinal = bl.copy(using: &bltrans) {
                path.addPath(blFinal)
            }

            // top right
            var tlt = CGAffineTransform(scaleX: -1, y: 1)
                .concatenating(CGAffineTransform(translationX: 90, y: 0))
                .concatenating(scaledTopLeft)

            var brtrans = CGAffineTransform(translationX: (dm * CGFloat(self.pixelSize)) - (9 * dm), y: 0)
            if let br = p.copy(using: &tlt), let brFinal = br.copy(using: &brtrans) {
                path.addPath(brFinal)
            }
        }

        // Add the pupils if wanted

        if components.contains(.eyePupil) {
            let p = eyeShape.pupilPath()
            var scaledTopLeft = scaleTransform.concatenating(posTransform)

            // top left
            if let tl = p.copy(using: &scaledTopLeft) {
                path.addPath(tl)
            }

            // bottom left
            var blt = CGAffineTransform(scaleX: 1, y: -1)
                .concatenating(CGAffineTransform(translationX: 0, y: 90))
                .concatenating(scaledTopLeft)

            var bltrans = CGAffineTransform(translationX: 0, y: (dm * CGFloat(self.pixelSize)) - (9 * dm))
            if let bl = p.copy(using: &blt), let blFinal = bl.copy(using: &bltrans) {
                path.addPath(blFinal)
            }

            // top right
            var tlt = CGAffineTransform(scaleX: -1, y: 1)
                .concatenating(CGAffineTransform(translationX: 90, y: 0))
                .concatenating(scaledTopLeft)

            var brtrans = CGAffineTransform(translationX: (dm * CGFloat(self.pixelSize)) - (9 * dm), y: 0)
            if let br = p.copy(using: &tlt), let brFinal = br.copy(using: &brtrans) {
                path.addPath(brFinal)
            }
        }

        // 'on' content
        if components.contains(.onPixels) {
            path.addPath(shape.onPixels.onPath(size: size, data: self))
        }

        return path
    }
}
