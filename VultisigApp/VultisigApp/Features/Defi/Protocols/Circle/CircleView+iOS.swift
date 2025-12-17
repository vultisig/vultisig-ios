//
//  CircleView+iOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

#if os(iOS)
extension CircleView {
    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
