//
//  StyledFloatingPointField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension StyledFloatingPointField {
    var container: some View {
        textField
            .keyboardType(.decimalPad)
    }
}
#endif
