//
//  HighlightedText.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/08/2025.
//

import SwiftUI

struct HighlightedText: View {
    let text: String
    let highlightedText: String

    var textStyle: (inout AttributedString) -> Void
    var highlightedTextStyle: (inout AttributedSubstring) -> Void

    var body: some View {
        Text(makeAttributedString())
    }

    private func makeAttributedString() -> AttributedString {
        // Convert to AttributedString
        var attributed = AttributedString(text)
        textStyle(&attributed)

        // Highlight parameters by finding their ranges
        if let highlightRange = attributed.range(of: highlightedText) {
            highlightedTextStyle(&attributed[highlightRange])
        }

        return attributed
    }
}
