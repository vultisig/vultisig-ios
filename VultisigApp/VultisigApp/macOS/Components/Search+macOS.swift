//
//  Search+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI

extension Search {
    var textField: some View {
        TextField(NSLocalizedString("search", comment: ""), text: $searchText)
            .foregroundColor(Theme.colors.textTertiary)
            .font(Theme.fonts.bodySRegular)
            .borderlessTextFieldStyle()
    }
}
#endif
