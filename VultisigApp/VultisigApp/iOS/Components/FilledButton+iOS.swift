//
//  FilledButton+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension FilledButton {
    var text: some View {
        Text(NSLocalizedString(title, comment: "Button Text"))
            .foregroundColor(.blue600)
            .font(.body16MontserratBold)
    }
}
#endif
