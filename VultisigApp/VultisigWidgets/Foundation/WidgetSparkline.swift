//
//  WidgetSparkline.swift
//  VultisigWidgets
//

import Charts
import SwiftUI
import WidgetKit

struct WidgetSparkline: View {
    let values: [Double]
    let isPositive: Bool
    var lineWidth: CGFloat = 2

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let domain {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    AreaMark(
                        x: .value("Position", index),
                        yStart: .value("Floor", domain.lowerBound),
                        yEnd: .value("Price", value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(areaGradient)

                    LineMark(
                        x: .value("Position", index),
                        y: .value("Price", value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }

                if let last = values.last {
                    PointMark(
                        x: .value("Position", max(0, values.count - 1)),
                        y: .value("Price", last)
                    )
                    .symbolSize(30)
                    .foregroundStyle(tint)
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .accessibilityHidden(true)
        }
    }

    private var tint: Color {
        isPositive ? WidgetTheme.positive : WidgetTheme.negative
    }

    private var areaGradient: LinearGradient {
        let opacity = renderingMode == .fullColor ? 0.28 : 0
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
}
