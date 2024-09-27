//
//  ColorStyle+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//

#if os(macOS)
import SwiftUI

extension Color {
    static let systemFill = Color(NSColor.systemFill)
    static let secondarySystemGroupedBackground = Color(NSColor.controlBackgroundColor)
    static let systemBackground = Color(NSColor.windowBackgroundColor)
}
#endif
