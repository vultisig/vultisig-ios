//
//  KeysignStartView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-22.
//

import SwiftUI

struct KeysignStartView: View {
    @ObservedObject var viewModel: JoinKeysignViewModel

    var body: some View {
        KeysignAnimationView(connected: .constant(false), coinLogo: nil)
            .task {
                await viewModel.waitForKeysignStart()
            }
    }
}

#Preview {
    KeysignStartView(viewModel: JoinKeysignViewModel())
}
