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
    /// Radius of the rounded junction where the arrow base blends into the
    /// tooltip body, so the triangle joins the bubble with a soft fillet
    /// instead of a hard kink (matches the design-system tooltip).
    let arrowJunctionRadius: CGFloat = 4
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

        // Unit vector along the arrow's slanted edge, used to place the
        // rounded-junction control points a fixed distance up each diagonal.
        let edgeLength = (pow(arrowWidth / 2, 2) + pow(arrowHeight, 2)).squareRoot()
        let edgeUX = (arrowWidth / 2) / edgeLength
        let edgeUY = arrowHeight / edgeLength
        let jr = arrowJunctionRadius

        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: bodyTop))
        // Left junction: fillet from the body top edge into the left diagonal.
        path.addLine(to: CGPoint(x: arrowLeft - jr, y: bodyTop))
        path.addQuadCurve(
            to: CGPoint(x: arrowLeft + edgeUX * jr, y: bodyTop - edgeUY * jr),
            control: CGPoint(x: arrowLeft, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: arrowCenterX - arrowCornerRadius, y: rect.minY + arrowCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: arrowCenterX + arrowCornerRadius, y: rect.minY + arrowCornerRadius),
            control: CGPoint(x: arrowCenterX, y: rect.minY)
        )
        // Right junction: fillet from the right diagonal back onto the body top.
        path.addLine(to: CGPoint(x: arrowRight - edgeUX * jr, y: bodyTop - edgeUY * jr))
        path.addQuadCurve(
            to: CGPoint(x: arrowRight + jr, y: bodyTop),
            control: CGPoint(x: arrowRight, y: bodyTop)
        )
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

        let edgeLength = (pow(arrowWidth / 2, 2) + pow(arrowHeight, 2)).squareRoot()
        let edgeUX = (arrowWidth / 2) / edgeLength
        let edgeUY = arrowHeight / edgeLength
        let jr = arrowJunctionRadius

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
        // Right junction: fillet from the body bottom edge into the right diagonal.
        path.addLine(to: CGPoint(x: arrowRight + jr, y: bodyBottom))
        path.addQuadCurve(
            to: CGPoint(x: arrowRight - edgeUX * jr, y: bodyBottom + edgeUY * jr),
            control: CGPoint(x: arrowRight, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: arrowCenterX + arrowCornerRadius, y: rect.maxY - arrowCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: arrowCenterX - arrowCornerRadius, y: rect.maxY - arrowCornerRadius),
            control: CGPoint(x: arrowCenterX, y: rect.maxY)
        )
        // Left junction: fillet from the left diagonal back onto the body bottom.
        path.addLine(to: CGPoint(x: arrowLeft + edgeUX * jr, y: bodyBottom + edgeUY * jr))
        path.addQuadCurve(
            to: CGPoint(x: arrowLeft - jr, y: bodyBottom),
            control: CGPoint(x: arrowLeft, y: bodyBottom)
        )
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
