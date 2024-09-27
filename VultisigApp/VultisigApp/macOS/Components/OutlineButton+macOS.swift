//
//  OutlineButton+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(macOS)
import SwiftUI

extension OutlineButton {
    var container: some View {
        content
            .font(.body14MontserratBold)
    }
    
    var overlay: some View {
        RoundedRectangle(cornerRadius: 100)
            .stroke(gradient, lineWidth: 2)
    }
}
#endif
