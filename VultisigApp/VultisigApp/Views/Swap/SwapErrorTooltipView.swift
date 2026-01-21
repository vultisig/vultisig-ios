//
//  SwapErrorTooltipView.swift
//  VultisigApp
//
//  Created by Vultisig on 2025-01-09.
//

import SwiftUI

struct SwapErrorTooltipView: View {
    let error: Error
    @Binding var showTooltip: Bool
    let onDismissTooltip: () -> Void

    private let circleIconSize: CGFloat = 20
    private let circleIconPadding: CGFloat = 7
    private var circleSize: CGFloat { circleIconSize + circleIconPadding * 2 }
    private let tooltipGap: CGFloat = 24

    var body: some View {
        warningIcon
            .overlay(alignment: .top) {
                if showTooltip {
                    tooltipContent
                        .fixedSize(horizontal: true, vertical: true)
                        .offset(y: circleSize + tooltipGap)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showTooltip)
    }

    var warningIcon: some View {
        Button {
            showTooltip.toggle()
        } label: {
            Icon(named: "circle-warning", color: .white, size: circleIconSize)
                .padding(circleIconPadding)
                .background(Circle().fill(Theme.colors.alertError))
        }
    }

    var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(errorTitle)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundColor(Theme.colors.textDark)

                Spacer()

                Button(action: onDismissTooltip) {
                    Icon(named: "x", color: Theme.colors.textButtonDisabled, size: 20)
                }
            }

            Text(errorDescription)
                .font(Theme.fonts.footnote)
                .foregroundColor(Theme.colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(Color(hex: "F5F5F5"))
        .clipShape(TooltipShape())
        .frame(maxWidth: 220)
    }

    private var errorTitle: String {
        if let swapError = error as? SwapCryptoLogic.Errors {
            return swapError.errorTitle
        }
        return SwapCryptoLogic.Errors.unexpectedError.errorTitle
    }

    private var errorDescription: String {
        if let swapError = error as? SwapCryptoLogic.Errors {
            return swapError.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }
}

struct TooltipShape: Shape {
    let cornerRadius: CGFloat = 16
    let topRightRadius: CGFloat = 4
    let arrowWidth: CGFloat = 20
    let arrowHeight: CGFloat = 10
    let arrowCornerRadius: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let arrowCenterX = rect.midX
        let arrowLeft = arrowCenterX - arrowWidth / 2
        let arrowRight = arrowCenterX + arrowWidth / 2
        let bodyTop = rect.minY + arrowHeight

        // Start from top-left corner (below arrow)
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: bodyTop))

        // Top-left edge to arrow left
        path.addLine(to: CGPoint(x: arrowLeft, y: bodyTop))

        // Arrow left side going up to near tip
        path.addLine(to: CGPoint(x: arrowCenterX - arrowCornerRadius, y: rect.minY + arrowCornerRadius))

        // Arrow tip (rounded)
        path.addQuadCurve(
            to: CGPoint(x: arrowCenterX + arrowCornerRadius, y: rect.minY + arrowCornerRadius),
            control: CGPoint(x: arrowCenterX, y: rect.minY)
        )

        // Arrow right side going down
        path.addLine(to: CGPoint(x: arrowRight, y: bodyTop))

        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - topRightRadius, y: bodyTop))

        // Top-right corner (smaller radius)
        path.addArc(
            center: CGPoint(x: rect.maxX - topRightRadius, y: bodyTop + topRightRadius),
            radius: topRightRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right edge to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))

        // Bottom-right corner
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))

        // Bottom-left corner
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge to top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop + cornerRadius))

        // Top-left corner
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
}

#Preview {
    ZStack {
        Theme.colors.bgPrimary.ignoresSafeArea()

        SwapErrorTooltipView(
            error: SwapCryptoLogic.Errors.insufficientFunds,
            showTooltip: .constant(true),
            onDismissTooltip: {}
        )
    }
}
