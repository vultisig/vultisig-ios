//
//  CustomHighlightText.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/12/2025.
//

import SwiftUI

struct CustomHighlightText: View {
    let text: String
    let highlightRanges: [(start: Int, end: Int, style: AnyShapeStyle)]

    // Convenience initializer with string matching
    init<S: ShapeStyle>(_ text: String, highlight: String, style: S) {
        self.text = text
        var ranges: [(Int, Int, AnyShapeStyle)] = []

        guard !highlight.isEmpty else {
            self.highlightRanges = ranges
            return
        }

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: highlight, range: searchRange) {
            let startIndex = text.distance(from: text.startIndex, to: range.lowerBound)
            let endIndex = text.distance(from: text.startIndex, to: range.upperBound)
            ranges.append((startIndex, endIndex, AnyShapeStyle(style)))

            // Continue searching after this match
            searchRange = range.upperBound..<text.endIndex
        }

        self.highlightRanges = ranges
    }

    init(_ text: String, highlights: [(String, LinearGradient)]) {
        self.text = text
        var ranges: [(Int, Int, AnyShapeStyle)] = []

        for (highlightText, gradient) in highlights {
            guard !highlightText.isEmpty else { continue }

            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: highlightText, range: searchRange) {
                let startIndex = text.distance(from: text.startIndex, to: range.lowerBound)
                let endIndex = text.distance(from: text.startIndex, to: range.upperBound)
                ranges.append((startIndex, endIndex, AnyShapeStyle(gradient)))

                searchRange = range.upperBound..<text.endIndex
            }
        }

        self.highlightRanges = ranges
    }

    var body: some View {
        gradientText
    }

    private var gradientText: Text {
        var result = Text("")
        var currentIndex = text.startIndex

        // Sort ranges by start position
        let sortedRanges = highlightRanges.sorted { $0.start < $1.start }

        for range in sortedRanges {
            let startIdx = text.index(text.startIndex, offsetBy: range.start)
            let endIdx = text.index(text.startIndex, offsetBy: range.end)

            // Skip this range if it starts before current position (overlap)
            guard startIdx >= currentIndex else { continue }

            // Add text before highlight
            if currentIndex < startIdx {
                result = result + Text(String(text[currentIndex..<startIdx]))
            }

            // Add highlighted text with style
            if startIdx < text.endIndex && endIdx <= text.endIndex {
                result = result + Text(String(text[startIdx..<endIdx]))
                    .foregroundStyle(range.style)
            }

            currentIndex = endIdx
        }

        // Add remaining text
        if currentIndex < text.endIndex {
            result = result + Text(String(text[currentIndex..<text.endIndex]))
        }

        return result
    }
}

#Preview {
    CustomHighlightText("This is a highlighted text", highlights: [("highlighted", LinearGradient.primaryGradient)])
}
