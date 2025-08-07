//
//  RedactedText.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/08/2025.
//

import SwiftUI

public struct RedactedText: View {
    let text: String
    let redactedText: String?
    @Binding var isLoading: Bool

    public init(_ text: String, redactedText: String?, isLoading: Binding<Bool>) {
        self.text = text
        self.redactedText = redactedText
        self._isLoading = isLoading
    }

    public var body: some View {
        Text(isLoading ? redactedText ?? "redacted" : text)
            .redacted(reason: isLoading ? .placeholder : [])
    }
}
