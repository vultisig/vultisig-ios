//
//  OutlinedDisclaimer+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//

#if os(iOS)
import SwiftUI

extension OutlinedDisclaimer {
    var overlay: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(LinearGradient.primaryGradient, lineWidth: 1)
    }
}
#endif
