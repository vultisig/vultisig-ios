//
//  RedactedText.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/08/2025.
//

import SwiftUI

struct RedactedText: View {
    let text: String
    let redactedText: String?
    @Binding var isLoading: Bool

    init(_ text: String, redactedText: String?, isLoading: Binding<Bool>) {
        self.text = text
        self.redactedText = redactedText
        self._isLoading = isLoading
    }

    var body: some View {
        Text(isLoading ? redactedText ?? "redacted" : text)
            .redacted(reason: isLoading ? .placeholder : [])
    }
}
