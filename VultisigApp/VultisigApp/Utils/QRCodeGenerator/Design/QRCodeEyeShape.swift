import CoreGraphics
import Foundation

struct QRCodeEyeShape {

    func eyePath() -> CGPath {
        let eyeOuterPath = CGMutablePath()
        eyeOuterPath.move(to: CGPoint(x: 45, y: 70))
        eyeOuterPath.curve(to: CGPoint(x: 23.98, y: 66.02), controlPoint1: CGPoint(x: 34.05, y: 70), controlPoint2: CGPoint(x: 27.96, y: 70))
        eyeOuterPath.curve(to: CGPoint(x: 20.58, y: 58.68), controlPoint1: CGPoint(x: 22.1, y: 64.14), controlPoint2: CGPoint(x: 21.11, y: 61.79))
        eyeOuterPath.curve(to: CGPoint(x: 20, y: 45), controlPoint1: CGPoint(x: 20, y: 55.21), controlPoint2: CGPoint(x: 20, y: 50.78))
        eyeOuterPath.curve(to: CGPoint(x: 23.98, y: 23.98), controlPoint1: CGPoint(x: 20, y: 34.05), controlPoint2: CGPoint(x: 20, y: 27.96))
        eyeOuterPath.curve(to: CGPoint(x: 45, y: 20), controlPoint1: CGPoint(x: 27.96, y: 20), controlPoint2: CGPoint(x: 34.05, y: 20))
        eyeOuterPath.curve(to: CGPoint(x: 66.02, y: 23.98), controlPoint1: CGPoint(x: 55.95, y: 20), controlPoint2: CGPoint(x: 62.04, y: 20))
        eyeOuterPath.curve(to: CGPoint(x: 70, y: 45), controlPoint1: CGPoint(x: 70, y: 27.96), controlPoint2: CGPoint(x: 70, y: 34.05))
        eyeOuterPath.curve(to: CGPoint(x: 66.02, y: 66.02), controlPoint1: CGPoint(x: 70, y: 55.95), controlPoint2: CGPoint(x: 70, y: 62.04))
        eyeOuterPath.curve(to: CGPoint(x: 45, y: 70), controlPoint1: CGPoint(x: 62.04, y: 70), controlPoint2: CGPoint(x: 55.95, y: 70))
        eyeOuterPath.close()
        eyeOuterPath.move(to: CGPoint(x: 74.43, y: 74.43))
        eyeOuterPath.curve(to: CGPoint(x: 80, y: 45), controlPoint1: CGPoint(x: 80, y: 68.86), controlPoint2: CGPoint(x: 80, y: 60.34))
        eyeOuterPath.curve(to: CGPoint(x: 74.43, y: 15.57), controlPoint1: CGPoint(x: 80, y: 29.66), controlPoint2: CGPoint(x: 80, y: 21.14))
        eyeOuterPath.curve(to: CGPoint(x: 45, y: 10), controlPoint1: CGPoint(x: 68.86, y: 10), controlPoint2: CGPoint(x: 60.34, y: 10))
        eyeOuterPath.curve(to: CGPoint(x: 15.57, y: 15.57), controlPoint1: CGPoint(x: 29.66, y: 10), controlPoint2: CGPoint(x: 21.14, y: 10))
        eyeOuterPath.curve(to: CGPoint(x: 10, y: 45), controlPoint1: CGPoint(x: 10, y: 21.14), controlPoint2: CGPoint(x: 10, y: 29.66))
        eyeOuterPath.curve(to: CGPoint(x: 12.05, y: 68.91), controlPoint1: CGPoint(x: 10, y: 56), controlPoint2: CGPoint(x: 10, y: 63.49))
        eyeOuterPath.curve(to: CGPoint(x: 15.57, y: 74.43), controlPoint1: CGPoint(x: 12.86, y: 71.04), controlPoint2: CGPoint(x: 13.99, y: 72.86))
        eyeOuterPath.curve(to: CGPoint(x: 45, y: 80), controlPoint1: CGPoint(x: 21.14, y: 80), controlPoint2: CGPoint(x: 29.66, y: 80))
        eyeOuterPath.curve(to: CGPoint(x: 74.43, y: 74.43), controlPoint1: CGPoint(x: 60.34, y: 80), controlPoint2: CGPoint(x: 68.86, y: 80))
        eyeOuterPath.close()
        return eyeOuterPath
    }

    public func pupilPath() -> CGPath {
        let eyePupilPath = CGMutablePath()
        eyePupilPath.move(to: CGPoint(x: 45, y: 30))
        eyePupilPath.curve(to: CGPoint(x: 57.61, y: 32.39), controlPoint1: CGPoint(x: 51.57, y: 30), controlPoint2: CGPoint(x: 55.23, y: 30))
        eyePupilPath.curve(to: CGPoint(x: 60, y: 45), controlPoint1: CGPoint(x: 60, y: 34.77), controlPoint2: CGPoint(x: 60, y: 38.43))
        eyePupilPath.curve(to: CGPoint(x: 57.61, y: 57.61), controlPoint1: CGPoint(x: 60, y: 51.57), controlPoint2: CGPoint(x: 60, y: 55.23))
        eyePupilPath.curve(to: CGPoint(x: 45, y: 60), controlPoint1: CGPoint(x: 55.23, y: 60), controlPoint2: CGPoint(x: 51.57, y: 60))
        eyePupilPath.curve(to: CGPoint(x: 32.39, y: 57.61), controlPoint1: CGPoint(x: 38.43, y: 60), controlPoint2: CGPoint(x: 34.77, y: 60))
        eyePupilPath.curve(to: CGPoint(x: 30, y: 45), controlPoint1: CGPoint(x: 30, y: 55.23), controlPoint2: CGPoint(x: 30, y: 51.57))
        eyePupilPath.curve(to: CGPoint(x: 32.39, y: 32.39), controlPoint1: CGPoint(x: 30, y: 38.43), controlPoint2: CGPoint(x: 30, y: 34.77))
        eyePupilPath.curve(to: CGPoint(x: 45, y: 30), controlPoint1: CGPoint(x: 34.77, y: 30), controlPoint2: CGPoint(x: 38.43, y: 30))
        eyePupilPath.close()
        return eyePupilPath
    }
}
