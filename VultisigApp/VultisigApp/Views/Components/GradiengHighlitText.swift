//
//  GradiengHighlitText.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/12/2025.
//

import SwiftUI

struct GradientHighlightText: View {
    let text: String
    let highlightRanges: [(start: Int, end: Int, gradient: LinearGradient)]
    
    // Primary initializer with index-based ranges
    init(_ text: String, highlightRanges: [(Int, Int, LinearGradient)]) {
        self.text = text
        self.highlightRanges = highlightRanges
    }
    
    // Convenience initializer with string matching (NEW!)
    init(_ text: String, highlight: String, gradient: LinearGradient) {
        self.text = text
        var ranges: [(Int, Int, LinearGradient)] = []
        
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: highlight, range: searchRange) {
            let startIndex = text.distance(from: text.startIndex, to: range.lowerBound)
            let endIndex = text.distance(from: text.startIndex, to: range.upperBound)
            ranges.append((startIndex, endIndex, gradient))
            
            // Continue searching after this match
            searchRange = range.upperBound..<text.endIndex
        }
        
        self.highlightRanges = ranges
    }
    
    // Convenience initializer with multiple string matches
    init(_ text: String, highlights: [(String, LinearGradient)]) {
        self.text = text
        var ranges: [(Int, Int, LinearGradient)] = []
        
        for (highlightText, gradient) in highlights {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: highlightText, range: searchRange) {
                let startIndex = text.distance(from: text.startIndex, to: range.lowerBound)
                let endIndex = text.distance(from: text.startIndex, to: range.upperBound)
                ranges.append((startIndex, endIndex, gradient))
                
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
            
            // Add text before highlight
            if currentIndex < startIdx {
                result = result + Text(String(text[currentIndex..<startIdx]))
                    .foregroundStyle(.white)
            }
            
            // Add highlighted text with gradient
            if startIdx < text.endIndex && endIdx <= text.endIndex {
                result = result + Text(String(text[startIdx..<endIdx]))
                    .foregroundStyle(range.gradient)
            }
            
            currentIndex = endIdx
        }
        
        // Add remaining text
        if currentIndex < text.endIndex {
            result = result + Text(String(text[currentIndex..<text.endIndex]))
                .foregroundStyle(.white)
        }
        
        return result
    }
}

#Preview {
    GradientHighlightText("This is a highlighted text", highlights: [("highlighted", LinearGradient.primaryGradient)])
}
