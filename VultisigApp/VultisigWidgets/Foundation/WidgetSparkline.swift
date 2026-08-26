//
//  WidgetSparkline.swift
//  VultisigWidgets
//

import SwiftUI
import WidgetKit

struct WidgetSparkline: View {
    let values: [Double]
    let isPositive: Bool?
    var lineWidth: CGFloat = 2
    var fillOpacity: Double = 0.20

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let domain, values.count > 1 {
            GeometryReader { proxy in
                let points = points(in: proxy.size, domain: domain)

                ZStack {
                    areaPath(points: points, size: proxy.size)
                        .fill(areaGradient)

                    linePath(points: points)
                        .stroke(
                            tint,
                            style: StrokeStyle(
                                lineWidth: lineWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    if let lastPoint = points.last {
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .overlay {
                                Circle()
                                    .stroke(WidgetTheme.primaryText, lineWidth: 1.5)
                            }
                            .position(lastPoint)
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var tint: Color {
        switch isPositive {
        case true:
            return WidgetTheme.positive
        case false:
            return WidgetTheme.negative
        case nil:
            return WidgetTheme.tertiaryText
        }
    }

    private var areaGradient: LinearGradient {
        let opacity = renderingMode == .fullColor ? fillOpacity : 0
        return LinearGradient(
            colors: [tint.opacity(opacity), tint.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var domain: ClosedRange<Double>? {
        guard let minimum = values.min(), let maximum = values.max() else { return nil }
        let span = maximum - minimum
        if span == 0 {
            let padding = max(abs(minimum) * 0.05, 1)
            return (minimum - padding)...(maximum + padding)
        }
        let padding = span * 0.08
        return (minimum - padding)...(maximum + padding)
    }

    private func points(in size: CGSize, domain: ClosedRange<Double>) -> [CGPoint] {
        let priceSpan = domain.upperBound - domain.lowerBound
        let xInterval = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let normalized = (value - domain.lowerBound) / priceSpan
            return CGPoint(
                x: CGFloat(index) * xInterval,
                y: size.height * (1 - CGFloat(normalized))
            )
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
    }

    private func areaPath(points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}
