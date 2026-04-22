//
//  TooltipShape.swift
//  VultisigApp
//

import SwiftUI

enum TooltipArrowDirection {
    case up
    case down
}

struct TooltipShape: Shape {
    let cornerRadius: CGFloat = 16
    let smallCornerRadius: CGFloat = 4
    let arrowWidth: CGFloat = 20
    let arrowHeight: CGFloat = 10
    let arrowCornerRadius: CGFloat = 2
    var arrowXFraction: CGFloat = 0.5
    var arrowDirection: TooltipArrowDirection = .up

    func path(in rect: CGRect) -> Path {
        switch arrowDirection {
        case .up:
            return topArrowPath(in: rect)
        case .down:
            return bottomArrowPath(in: rect)
        }
    }

    private func topArrowPath(in rect: CGRect) -> Path {
        var path = Path()

        let arrowCenterX = rect.minX + rect.width * arrowXFraction
        let arrowLeft = arrowCenterX - arrowWidth / 2
        let arrowRight = arrowCenterX + arrowWidth / 2
        let bodyTop = rect.minY + arrowHeight

        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: bodyTop))
        path.addLine(to: CGPoint(x: arrowLeft, y: bodyTop))
        path.addLine(to: CGPoint(x: arrowCenterX - arrowCornerRadius, y: rect.minY + arrowCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: arrowCenterX + arrowCornerRadius, y: rect.minY + arrowCornerRadius),
            control: CGPoint(x: arrowCenterX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: arrowRight, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX - smallCornerRadius, y: bodyTop))
        path.addArc(
            center: CGPoint(x: rect.maxX - smallCornerRadius, y: bodyTop + smallCornerRadius),
            radius: smallCornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: bodyTop + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }

    private func bottomArrowPath(in rect: CGRect) -> Path {
        var path = Path()

        let arrowCenterX = rect.minX + rect.width * arrowXFraction
        let arrowLeft = arrowCenterX - arrowWidth / 2
        let arrowRight = arrowCenterX + arrowWidth / 2
        let bodyBottom = rect.maxY - arrowHeight

        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - smallCornerRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - smallCornerRadius, y: rect.minY + smallCornerRadius),
            radius: smallCornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: bodyBottom - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: arrowRight, y: bodyBottom))
        path.addLine(to: CGPoint(x: arrowCenterX + arrowCornerRadius, y: rect.maxY - arrowCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: arrowCenterX - arrowCornerRadius, y: rect.maxY - arrowCornerRadius),
            control: CGPoint(x: arrowCenterX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: arrowLeft, y: bodyBottom))
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: bodyBottom))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: bodyBottom - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}
