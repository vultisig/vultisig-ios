//
//  HighlightedTextWithImage.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI

struct HighlightedTextWithImage: View {
    let text: String
    let highlightedText: String
    let imageName: String
    let font: Font
    let foregroundColor: Color

    var body: some View {
        // Find the range of the highlighted text
        if let range = text.range(of: highlightedText) {
            let beforeText = String(text[..<range.lowerBound])
            let afterText = String(text[range.upperBound...])

            // Compose the text with image overlay on highlighted portion
            HStack(spacing: 0) {
                if !beforeText.isEmpty {
                    Text(beforeText)
                        .font(font)
                        .foregroundColor(foregroundColor)
                }

                Text(highlightedText)
                    .font(font)
                    .foregroundColor(.clear)
                    .overlay {
                        Image(imageName)
                            .resizable()
                            .scaledToFill()
                            .mask(
                                Text(highlightedText)
                                    .font(font)
                            )
                    }

                if !afterText.isEmpty {
                    Text(afterText)
                        .font(font)
                        .foregroundColor(foregroundColor)
                }
            }
        } else {
            // Fallback if highlighted text not found
            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
        }
    }
}
