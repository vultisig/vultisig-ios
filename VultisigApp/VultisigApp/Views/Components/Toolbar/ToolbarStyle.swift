//
//  ToolbarStyle.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/09/2025.
//

import SwiftUI

struct ToolbarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            Label(configuration)
        } else {
            Label(configuration)
                .labelStyle(.titleOnly)
        }
    }
}

@available(iOS, introduced: 17, obsoleted: 26, message: "Remove this property in iOS 26")
extension LabelStyle where Self == ToolbarLabelStyle {
    static var toolbar: Self { .init() }
}
