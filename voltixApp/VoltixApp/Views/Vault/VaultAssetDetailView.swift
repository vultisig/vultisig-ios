//
//  VaultAssetDetailView.swift
//  VoltixApp
//

import SwiftUI

struct VaultAssetDetailView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    let type: AssetType
    
    var body: some View {
        VStack(alignment: .leading) {
          VStack(alignment: .leading) {
            HStack() {
                Text("Ethereum")
                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                    
                Spacer().frame(width: 30)
                Button(action: {}) {
                    Image("Copy")
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Spacer().frame(width: 40)
                Button(action: {}) {
                    Image("Link")
                        .resizable()
                        .frame(width: 16, height: 20)
                }
                Spacer().frame(width: 40)
                Button(action: {}) {
                    Image("QR")
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Spacer()
                Text("$65,899")
                    .font(Font.custom("Menlo", size: 20))
                    .multilineTextAlignment(.trailing)
                    
            }
            Spacer()
            HStack() {
                Text("0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4")
                    .font(Font.custom("Montserrat", size: 13).weight(.medium))
                    .lineSpacing(19.50)
                    ;
            }
          }
          .frame(width: .infinity, height: 83)
          Choose(content: "TOKENS")
            Spacer()
        }
        .padding()
        .navigationTitle("VAULT")
        .modifier(InlineNavigationBarTitleModifier())
        .toolbar {
          #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
              NavigationButtons.questionMarkButton
            }
          #else
            ToolbarItem {
              NavigationButtons.backButton(presentationStack: $presentationStack)
            }
            ToolbarItem {
              NavigationButtons.questionMarkButton
            }
          #endif
        }
    }
}

#Preview {
    VaultAssetDetailView(presentationStack: .constant([]), type: .bitcoin)
}
