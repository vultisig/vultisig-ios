//
//  RefreshToolbarButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 14/10/2025.
//

import SwiftUI

struct RefreshToolbarButton: View {
    @Binding var isRefreshing: Bool
    var onRefresh: () -> Void
    
    @State private var isRefreshingInternal = false
    
    var body: some View {
        ToolbarButton(image: "refresh", action: onRefresh) { icon in
            icon
                .rotationEffect(.degrees(isRefreshingInternal ? 360 : 0))
                .animation(isRefreshingInternal ? .easeInOut(duration: 1) : nil, value: isRefreshingInternal)
        }
        .disabled(isRefreshingInternal)
        .onChange(of: isRefreshing) { _, newValue in
            withAnimation {
                isRefreshingInternal = newValue
            }
        }
    }
}
