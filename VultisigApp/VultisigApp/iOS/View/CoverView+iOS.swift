//
//  CoverView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(iOS)
import SwiftUI

extension CoverView {
    var container: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
    }
}
#endif
