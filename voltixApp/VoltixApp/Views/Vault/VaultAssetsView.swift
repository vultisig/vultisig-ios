//
//  VaultView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetsView: View {
  @Binding var presentationStack: [CurrentScreen]

  //var body: some View {
  //    Text("VaultAssetsView")
  //    List(AssetType.allCases, id: \.self) { asset in
  //       Button(asset.chainName) {
  //           presentationStack.append(.vaultDetailAsset(asset))
  //        }
  //   }
  //}

  var body: some View {
    VStack(alignment: .leading) {
      HeaderView(
        rightIcon: "Refresh",
        leftIcon: "Menu",
        head: "VAULT",
        leftAction: {},
        rightAction: {}
      )
    }
  }
}

#Preview {
  VaultAssetsView(presentationStack: .constant([]))
}

/*
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
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: 0,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
*/
