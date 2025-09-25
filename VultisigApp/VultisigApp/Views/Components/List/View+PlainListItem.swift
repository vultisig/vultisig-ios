//
//  View+PlainListItem.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/09/2025.
//

import SwiftUI

extension View {
    func plainListItem() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
}
