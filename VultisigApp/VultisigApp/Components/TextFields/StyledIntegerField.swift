//
//  StyledIntegerField.swift
//  VultisigApp
//

import SwiftUI

#if os(iOS)
import SwiftUI

extension StyledIntegerField {
    var container: some View {
        textField
            .keyboardType(.numberPad)
    }
}
#endif

#if os(macOS)
import SwiftUI

extension StyledIntegerField {
    var container: some View {
        textField
    }
}
#endif
