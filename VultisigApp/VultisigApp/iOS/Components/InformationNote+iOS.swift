//
//  InformationNote+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//

#if os(iOS)
import SwiftUI

extension InformationNote {
    var overlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.warningYellow, lineWidth: 1)
    }
}
#endif
