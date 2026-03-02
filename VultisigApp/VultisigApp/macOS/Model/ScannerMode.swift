//
//  ScannerMode.swift
//  VultisigApp
//

#if os(macOS)
import Foundation

enum ScannerMode: Int, FilledSegmentedControlType, CaseIterable {
    case camera = 0
    case screen = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .camera:
            return NSLocalizedString("scannerModeCamera", comment: "")
        case .screen:
            return NSLocalizedString("scannerModeScreen", comment: "")
        }
    }
}
#endif
