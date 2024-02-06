//
//  VaultView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetsView: View {
    @Binding var presentationStack: [CurrentScreen]
    @EnvironmentObject var appState: ApplicationState

    @State private var signingTestView = false
    var body: some View {
        VStack {
            if signingTestView {
                KeysignTestView(presentationStack: $presentationStack)
            } else {
                HStack {
                    Button("Sign stuff") {
                        signingTestView = true
                    }

                    Button("Join keysign stuff") {
                        presentationStack.append(.JoinKeysign)
                    }
                }
            }
        }
    }
}

#Preview {
    VaultAssetsView(presentationStack: .constant([]))
}
