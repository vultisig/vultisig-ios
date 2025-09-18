//
//  TabBarItem.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/09/2025.
//

import SwiftUI

protocol TabBarItem: Hashable, Identifiable {
    var name: String { get }
    var icon: String { get }
}

extension TabBarItem {
    var id: String { name }
}
