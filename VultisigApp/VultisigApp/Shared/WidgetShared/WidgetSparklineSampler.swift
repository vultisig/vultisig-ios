//
//  WidgetSparklineSampler.swift
//  VultisigApp
//

import Foundation

enum WidgetSparklineSampler {
    static let defaultPointCount = 28

    static func resample(_ values: [Double], to targetCount: Int = defaultPointCount) -> [Double] {
        guard targetCount > 1, values.count > targetCount else { return values }

        let lastIndex = Double(values.count - 1)
        let interval = lastIndex / Double(targetCount - 1)

        return (0..<targetCount).map { outputIndex in
            let sourcePosition = Double(outputIndex) * interval
            let lowerIndex = Int(sourcePosition.rounded(.down))
            let upperIndex = min(lowerIndex + 1, values.count - 1)
            let fraction = sourcePosition - Double(lowerIndex)
            return values[lowerIndex] + ((values[upperIndex] - values[lowerIndex]) * fraction)
        }
    }
}
