//
//  OutlineButton+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension OutlineButton {
    var container: some View {
        content
            .font(.body16MontserratBold)
    }
    
    var overlay: some View {
        RoundedRectangle(cornerRadius: 100)
            .stroke(gradient, lineWidth: 1)
    }
}
#endif
