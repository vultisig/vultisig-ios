//
//  NetworkPromptType.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

enum NetworkPromptType: String, CaseIterable {
    case Internet
    case Local

    func getImage() -> Image {
        let name: String

        switch self {
        case .Internet:
            name = "cellularbars"
        case .Local:
            name = "wifi"
        }

        return Image(systemName: name)
    }

    func getInstruction() -> String {
        let title: String

        switch self {
        case .Internet:
            title = "devicesOnSameInternet"
        case .Local:
            title = "devicesOnSameNetwork"
        }

        return NSLocalizedString(title, comment: "")
    }
}
