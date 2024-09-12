//
//  StyledFloatingPointField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(macOS)
import SwiftUI

extension StyledFloatingPointField {
    var container: some View {
        textField
    }
}
#endif
