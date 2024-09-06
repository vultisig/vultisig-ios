//
//  ContentView+MacOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(macOS)
import SwiftUI

extension ContentView {
    var container: some View {
        content
            .navigationTitle("Vultisig")
    }
}
#endif
