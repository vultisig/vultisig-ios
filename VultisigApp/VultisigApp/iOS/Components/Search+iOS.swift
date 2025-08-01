//
//  Search+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(iOS)
import SwiftUI

extension Search {
    var textField: some View {
        TextField(NSLocalizedString("search", comment: ""), text: $searchText)
            .foregroundColor(.neutral700)
            .font(theme.fonts.bodySRegular)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button {
                        hideKeyboard()
                    } label: {
                        Text(NSLocalizedString("done", comment: ""))
                    }
                }
            }
            .borderlessTextFieldStyle()
    }
}
#endif
