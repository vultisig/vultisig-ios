//
//  FastVaultEnterPasswordView+iOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 14.09.2024.
//

import SwiftUI

extension FastVaultEnterPasswordView {

#if os(iOS)
    var body: some View {
        NavigationView {
            ZStack {
                Background()
                VStack {
                    view
                }
            }
            .navigationBarTitleTextColor(.neutral0)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Password")
        }
    }
#endif
}
