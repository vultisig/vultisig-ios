//
//  TabBarItem.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/09/2025.
//

import SwiftUI

protocol TabBarItem: Hashable, Identifiable {
    var name: String { get }
    var icon: ImageResource { get }
    var accessibilityID: String? { get }
}

extension TabBarItem {
    var id: String { name }
    var accessibilityID: String? { nil }
}
