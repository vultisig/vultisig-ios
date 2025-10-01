//
//  MacOSToolbarView.swift
//  VultisigApp
//
//  Created by Assistant on 30/09/2025.
//

import SwiftUI

#if os(macOS)
struct MacOSToolbarView<Content: View>: View {
    let items: [CustomToolbarItem]
    let navigationTitle: String?
    let content: Content
    
    init(
        items: [CustomToolbarItem],
        navigationTitle: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.items = items
        self.navigationTitle = navigationTitle
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Content
            content
            
            // macOS toolbar with transparent background
            HStack(alignment: .center) {
                // Leading items
                ForEach(Array(leadingItems.enumerated()), id: \.offset) { _, item in
                    item.content
                }
                
                Spacer()
                
                // Navigation title in the center
                if let navigationTitle {
                    Text(navigationTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Trailing items
                ForEach(Array(trailingItems.enumerated()), id: \.offset) { _, item in
                    item.content
                }
            }
            .frame(height: 60)
            .padding(.horizontal, 16)
        }
    }
    
    private var leadingItems: [CustomToolbarItem] {
        items.filter { $0.placement == .leading }
    }
    
    private var trailingItems: [CustomToolbarItem] {
        items.filter { $0.placement == .trailing }
    }
}
#endif
