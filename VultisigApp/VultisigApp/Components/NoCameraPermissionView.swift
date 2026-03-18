//
//  NoCameraPermissionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//

import SwiftUI

struct NoCameraPermissionView: View {
    var body: some View {
        ErrorView(
            type: .warning,
            title: "noCameraPermissionError".localized,
            description: "",
            buttonTitle: "openSettings".localized,
            action: openSettings
        )
    }
}

#Preview {
    NoCameraPermissionView()
}
