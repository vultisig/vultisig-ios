//
//  ContentView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(iOS)
import SwiftUI

extension ContentView {
    var container: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarTitleTextColor(.neutral0)
    }
}
#endif
